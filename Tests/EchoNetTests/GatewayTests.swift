import Testing
import Foundation
@testable import EchoNet

final class StubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var body = Data("{}".utf8)
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for r: URLRequest) -> URLRequest { r }
    override func startLoading() {
        let r = HTTPURLResponse(url: request.url!, statusCode: request.url!.path.contains("limited") ? 429 : 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: r, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

func stubGateway(store: URL? = nil) -> NetworkGateway {
    let cfg = URLSessionConfiguration.ephemeral; cfg.protocolClasses = [StubProtocol.self]
    return NetworkGateway(session: URLSession(configuration: cfg), storeURL: store)
}

@Test func gatewayRecordsEveryRequest() async throws {
    let g = stubGateway()
    await g.setMeeting("m1")
    var req = URLRequest(url: URL(string: "https://example.com/v1/x")!); req.httpMethod = "POST"; req.httpBody = Data("hello".utf8)
    _ = try await g.data(for: req, purpose: "test", provider: "Stub", containsMeetingData: true)
    let e = await g.entries()
    #expect(e.count == 1)
    #expect(e[0].host == "example.com" && e[0].bytesSent == 5 && e[0].containsMeetingData && e[0].meetingID == "m1")
    #expect(await g.meetingDataBytes(forMeeting: "m1") == 5)
}
@Test func gatewayMapsRateLimit() async {
    let g = stubGateway()
    do { _ = try await g.data(for: URLRequest(url: URL(string: "https://example.com/limited")!), purpose: "t", provider: "S", containsMeetingData: false); Issue.record("no throw") }
    catch GatewayError.rateLimited { } catch { Issue.record("wrong error \(error)") }
    #expect(await g.entries().count == 1)
}
@Test func ledgerPersistsAcrossLaunches() async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("ledger-\(UUID()).jsonl")
    let g1 = stubGateway(store: url)
    _ = try await g1.data(for: URLRequest(url: URL(string: "https://example.com/a")!), purpose: "t", provider: "S", containsMeetingData: false)
    let g2 = stubGateway(store: url)
    #expect(await g2.entries().count == 1)
}

/// F13: only EchoNet may touch URLSession, so the Privacy Ledger sees every request.
@Test func noURLSessionOutsideEchoNet() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources")
    let fm = FileManager.default
    var offenders: [String] = []
    for case let url as URL in fm.enumerator(at: root, includingPropertiesForKeys: nil)! where url.pathExtension == "swift" {
        if url.path.contains("/Sources/EchoNet/") { continue }
        let text = try String(contentsOf: url, encoding: .utf8)
        if text.contains("URLSession") || text.contains("NSURLConnection") { offenders.append(url.lastPathComponent) }
    }
    #expect(offenders.isEmpty, "Network code outside EchoNet: \(offenders)")
}
