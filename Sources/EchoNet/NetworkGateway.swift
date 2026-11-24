import Foundation

public struct LedgerEntry: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var time: Date
    public var method: String
    public var host: String
    public var path: String
    public var bytesSent: Int
    public var bytesReceived: Int
    public var purpose: String
    public var provider: String
    /// True when the request body contained transcript text or audio from a meeting.
    public var containsMeetingData: Bool
    public var status: Int
    public var meetingID: String?
}

public enum GatewayError: Error, CustomStringConvertible {
    case rateLimited(retryAfter: TimeInterval?)
    case http(Int, String)
    case badResponse
    public var description: String {
        switch self {
        case .rateLimited: return "Rate limited (HTTP 429)"
        case .http(let c, let m): return "HTTP \(c): \(m)"
        case .badResponse: return "Unexpected response"
        }
    }
}

/// The ONLY place in Chitter that talks to the network. Every request is recorded in the Privacy Ledger.
/// (A unit test fails the build if any other module mentions URLSession.)
public actor NetworkGateway {
    public static let shared = NetworkGateway()
    private let session: URLSession
    private var log: [LedgerEntry] = []
    private let storeURL: URL?
    private var continuations: [UUID: AsyncStream<LedgerEntry>.Continuation] = [:]
    public var currentMeetingID: String?

    public init(session: URLSession = .shared, storeURL: URL? = NetworkGateway.defaultStoreURL) {
        self.session = session
        self.storeURL = storeURL
        if let storeURL, let text = try? String(contentsOf: storeURL, encoding: .utf8) {
            let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
            log = text.split(separator: "\n").compactMap { try? dec.decode(LedgerEntry.self, from: Data($0.utf8)) }
        }
    }

    public static var defaultStoreURL: URL? {
        guard let base = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        else { return nil }
        let dir = base.appendingPathComponent("Chitter", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return dir.appendingPathComponent("ledger.jsonl")
    }

    public func setMeeting(_ id: String?) { currentMeetingID = id }
    public func entries(forMeeting id: String? = nil) -> [LedgerEntry] {
        id == nil ? log : log.filter { $0.meetingID == id }
    }
    public func meetingDataBytes(forMeeting id: String) -> Int {
        log.filter { $0.meetingID == id && $0.containsMeetingData }.reduce(0) { $0 + $1.bytesSent }
    }
    public func updates() -> AsyncStream<LedgerEntry> {
        let key = UUID()
        return AsyncStream { c in
            continuations[key] = c
            c.onTermination = { [weak self] _ in Task { await self?.drop(key) } }
        }
    }
    private func drop(_ k: UUID) { continuations[k] = nil }

    /// Records an event the gateway can't see directly (e.g. an OS-managed model download) so the ledger stays honest.
    public func note(host: String, purpose: String, provider: String, bytes: Int = 0) {
        record(LedgerEntry(id: UUID(), time: Date(), method: "OS", host: host, path: "", bytesSent: 0, bytesReceived: bytes,
                           purpose: purpose, provider: provider, containsMeetingData: false, status: 0, meetingID: nil))
    }

    public func data(for request: URLRequest, purpose: String, provider: String,
                     containsMeetingData: Bool) async throws -> (Data, HTTPURLResponse) {
        let sent = request.httpBody?.count ?? 0
        var entry = LedgerEntry(id: UUID(), time: Date(), method: request.httpMethod ?? "GET",
                                host: request.url?.host ?? "?", path: request.url?.path ?? "",
                                bytesSent: sent, bytesReceived: 0, purpose: purpose, provider: provider,
                                containsMeetingData: containsMeetingData, status: 0,
                                meetingID: containsMeetingData ? currentMeetingID : nil)
        do {
            let (data, resp) = try await session.data(for: request)
            guard let http = resp as? HTTPURLResponse else { throw GatewayError.badResponse }
            entry.bytesReceived = data.count; entry.status = http.statusCode
            record(entry)
            if http.statusCode == 429 {
                throw GatewayError.rateLimited(retryAfter: (http.value(forHTTPHeaderField: "Retry-After")).flatMap(Double.init))
            }
            guard (200..<300).contains(http.statusCode) else {
                throw GatewayError.http(http.statusCode, String(decoding: data.prefix(200), as: UTF8.self))
            }
            return (data, http)
        } catch let e as GatewayError { throw e } catch { entry.status = -1; record(entry); throw error }
    }

    /// Downloads a file (installers, models). Not meeting data.
    public func download(_ url: URL, to dest: URL, purpose: String, provider: String) async throws {
        let (tmp, resp) = try await session.download(from: url)
        let size = (try? FileManager.default.attributesOfItem(atPath: tmp.path)[.size] as? Int) ?? 0
        record(LedgerEntry(id: UUID(), time: Date(), method: "GET", host: url.host ?? "?", path: url.path, bytesSent: 0,
                           bytesReceived: size, purpose: purpose, provider: provider, containsMeetingData: false,
                           status: (resp as? HTTPURLResponse)?.statusCode ?? 0, meetingID: nil))
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tmp, to: dest)
    }

    private func record(_ e: LedgerEntry) {
        log.append(e)
        for c in continuations.values { c.yield(e) }
        guard let storeURL else { return }
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        guard let line = try? enc.encode(e) else { return }
        if let h = try? FileHandle(forWritingTo: storeURL) {
            h.seekToEndOfFile(); h.write(line); h.write(Data("\n".utf8)); try? h.close()
        } else {
            try? (line + Data("\n".utf8)).write(to: storeURL, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: storeURL.path)
        }
    }
}
