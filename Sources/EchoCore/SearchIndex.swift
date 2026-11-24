import Foundation
import SQLite3

public struct SearchHit: Equatable, Sendable { public var meetingID: String; public var lineID: Int; public var text: String; public var fuzzy: Bool }

/// Global SQLite FTS5 index across all meetings (trigram tokenizer = substring search), plus an
/// edit-distance fallback so near spellings ("Marria") still find "Maria".
public final class SearchIndex: @unchecked Sendable {
    private var db: OpaquePointer?
    private let lock = NSLock()

    public init(path: String) throws {
        if sqlite3_open(path, &db) != SQLITE_OK { throw NSError(domain: "SearchIndex", code: 1) }
        try exec("CREATE VIRTUAL TABLE IF NOT EXISTS lines USING fts5(text, meeting UNINDEXED, line UNINDEXED, tokenize='trigram')")
    }
    public static func defaultPath() -> String {
        let base = MeetingStore.defaultRoot.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("index.sqlite").path
    }
    deinit { sqlite3_close(db) }

    @discardableResult private func exec(_ sql: String) throws -> Int32 {
        var err: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &err)
        if rc != SQLITE_OK { let m = err.map { String(cString: $0) } ?? "sqlite"; sqlite3_free(err); throw NSError(domain: "SQLite", code: Int(rc), userInfo: [NSLocalizedDescriptionKey: m]) }
        return rc
    }

    public func index(meetingID: String, segments: [Segment]) {
        lock.lock(); defer { lock.unlock() }
        try? exec("BEGIN")
        remove(meetingID: meetingID, locked: true)
        var st: OpaquePointer?
        sqlite3_prepare_v2(db, "INSERT INTO lines(text, meeting, line) VALUES (?, ?, ?)", -1, &st, nil)
        for s in segments {
            let text = s.translation.map { s.text + " \n" + $0 } ?? s.text
            sqlite3_bind_text(st, 1, text, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_text(st, 2, meetingID, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_int(st, 3, Int32(s.id))
            sqlite3_step(st); sqlite3_reset(st)
        }
        sqlite3_finalize(st)
        try? exec("COMMIT")
    }

    public func remove(meetingID: String) { lock.lock(); defer { lock.unlock() }; remove(meetingID: meetingID, locked: true) }
    private func remove(meetingID: String, locked: Bool) {
        var st: OpaquePointer?
        sqlite3_prepare_v2(db, "DELETE FROM lines WHERE meeting = ?", -1, &st, nil)
        sqlite3_bind_text(st, 1, meetingID, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_step(st); sqlite3_finalize(st)
    }

    private func all() -> [SearchHit] {
        var out: [SearchHit] = []; var st: OpaquePointer?
        sqlite3_prepare_v2(db, "SELECT meeting, line, text FROM lines", -1, &st, nil)
        while sqlite3_step(st) == SQLITE_ROW {
            out.append(SearchHit(meetingID: String(cString: sqlite3_column_text(st, 0)), lineID: Int(sqlite3_column_int(st, 1)),
                                 text: String(cString: sqlite3_column_text(st, 2)), fuzzy: true))
        }
        sqlite3_finalize(st); return out
    }

    public func search(_ query: String, limit: Int = 50) -> [SearchHit] {
        lock.lock(); defer { lock.unlock() }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        var hits: [SearchHit] = []
        if q.count >= 3 {
            var st: OpaquePointer?
            let phrase = "\"" + q.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            if sqlite3_prepare_v2(db, "SELECT meeting, line, text FROM lines WHERE lines MATCH ? LIMIT ?", -1, &st, nil) == SQLITE_OK {
                sqlite3_bind_text(st, 1, phrase, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                sqlite3_bind_int(st, 2, Int32(limit))
                while sqlite3_step(st) == SQLITE_ROW {
                    hits.append(SearchHit(meetingID: String(cString: sqlite3_column_text(st, 0)), lineID: Int(sqlite3_column_int(st, 1)),
                                          text: String(cString: sqlite3_column_text(st, 2)), fuzzy: false))
                }
            }
            sqlite3_finalize(st)
        }
        if hits.count < limit {   // fuzzy fallback: any word within edit distance ≤ 2 (≤1 for short words)
            let qw = q.lowercased(); let maxD = qw.count <= 4 ? 1 : 2
            let have = Set(hits.map { "\($0.meetingID)#\($0.lineID)" })
            for h in all() where !have.contains("\(h.meetingID)#\(h.lineID)") {
                if h.text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains(where: { Self.distance(String($0), qw) <= maxD }) {
                    hits.append(h); if hits.count >= limit { break }
                }
            }
        }
        return hits
    }

    public static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }; if b.isEmpty { return a.count }
        var prev = Array(0...b.count)
        for i in 1...a.count {
            var cur = [i] + [Int](repeating: 0, count: b.count)
            for j in 1...b.count { cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)) }
            prev = cur
        }
        return prev[b.count]
    }
}
