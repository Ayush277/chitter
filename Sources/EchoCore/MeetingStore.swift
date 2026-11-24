import Foundation

/// Plain-file meeting storage (Obsidian-friendly): one folder per meeting.
///   meeting.json · transcript.jsonl (append-only, crash-safe) · notes.md · audio.m4a (optional)
public final class MeetingStore: @unchecked Sendable {
    public let root: URL
    private let fm = FileManager.default

    public static var defaultRoot: URL {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Chitter/meetings", isDirectory: true)
    }

    public init(root: URL = MeetingStore.defaultRoot) {
        self.root = root
        try? fm.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var url = root; var rv = URLResourceValues(); rv.isExcludedFromBackup = true   // keep out of Time Machine
        try? url.setResourceValues(rv)
    }

    static func slug(_ s: String) -> String {
        let allowed = s.lowercased().map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
        let collapsed = allowed.split(separator: "-").joined(separator: "-")
        return String(collapsed.prefix(40)).isEmpty ? "meeting" : String(collapsed.prefix(40))
    }

    public func create(title: String = "Meeting", date: Date = Date(), sourceLanguage: String? = nil,
                       targetLanguage: String? = nil) throws -> MeetingHandle {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd_HHmm"; f.locale = Locale(identifier: "en_US_POSIX")
        var id = "\(f.string(from: date))_\(Self.slug(title))", n = 2
        while fm.fileExists(atPath: root.appendingPathComponent(id).path) { id = "\(f.string(from: date))_\(Self.slug(title))-\(n)"; n += 1 }
        let dir = root.appendingPathComponent(id, isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let info = MeetingInfo(id: id, title: title, startedAt: date, sourceLanguage: sourceLanguage, targetLanguage: targetLanguage)
        let h = MeetingHandle(dir: dir, info: info)
        try h.writeInfo()
        fm.createFile(atPath: h.transcriptURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        return h
    }

    public func list() -> [MeetingInfo] {
        let dirs = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return dirs.compactMap { try? dec.decode(MeetingInfo.self, from: Data(contentsOf: $0.appendingPathComponent("meeting.json"))) }
            .sorted { $0.startedAt > $1.startedAt }
    }

    public func open(_ id: String) -> MeetingHandle? {
        let dir = root.appendingPathComponent(id, isDirectory: true)
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        guard let info = try? dec.decode(MeetingInfo.self, from: Data(contentsOf: dir.appendingPathComponent("meeting.json"))) else { return nil }
        return MeetingHandle(dir: dir, info: info)
    }

    public func delete(_ id: String) throws { try fm.removeItem(at: root.appendingPathComponent(id)) }
}

public final class MeetingHandle: @unchecked Sendable {
    public let dir: URL
    public private(set) var info: MeetingInfo
    private let lock = NSLock()
    private var writer: FileHandle?

    init(dir: URL, info: MeetingInfo) { self.dir = dir; self.info = info }

    public var transcriptURL: URL { dir.appendingPathComponent("transcript.jsonl") }
    public var notesURL: URL { dir.appendingPathComponent("notes.md") }
    public var notesJSONURL: URL { dir.appendingPathComponent("notes.json") }
    public var audioURL: URL { dir.appendingPathComponent("audio.m4a") }

    func writeInfo() throws {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let url = dir.appendingPathComponent("meeting.json")
        try enc.encode(info).write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public func update(_ change: (inout MeetingInfo) -> Void) { lock.lock(); change(&info); lock.unlock(); try? writeInfo() }

    /// Appends one JSON line. Re-appending a segment with the same `id` supersedes the earlier line (e.g. when its translation arrives).
    public func append(_ s: Segment) {
        lock.lock(); defer { lock.unlock() }
        if writer == nil { writer = try? FileHandle(forWritingTo: transcriptURL); _ = try? writer?.seekToEnd() }
        guard let data = try? JSONEncoder().encode(s) else { return }
        writer?.write(data); writer?.write(Data("\n".utf8))
        try? writer?.synchronize()   // crash-safe: each line hits disk
    }

    public func loadSegments() -> [Segment] {
        guard let text = try? String(contentsOf: transcriptURL, encoding: .utf8) else { return [] }
        var byID: [Int: Segment] = [:]
        for line in text.split(separator: "\n") {
            // A torn final line after a crash is simply skipped.
            if let s = try? JSONDecoder().decode(Segment.self, from: Data(line.utf8)) { byID[s.id] = s }
        }
        return byID.values.sorted { $0.id < $1.id }
    }

    public func finish(at date: Date = Date()) {
        lock.lock(); try? writer?.close(); writer = nil; lock.unlock()
        update { $0.endedAt = date }
    }
    deinit { try? writer?.close() }
}
