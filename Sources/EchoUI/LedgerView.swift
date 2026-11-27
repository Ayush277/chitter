import SwiftUI
import EchoCore
import EchoNet

@MainActor
public final class LedgerModel: ObservableObject {
    @Published public var entries: [LedgerEntry] = []
    @Published public var meetingID: String?          // nil = all time
    private var task: Task<Void, Never>?
    public init() {}
    public func start() {
        task?.cancel()
        task = Task { [weak self] in
            guard let self else { return }
            self.entries = await NetworkGateway.shared.entries()
            for await _ in await NetworkGateway.shared.updates() { self.entries = await NetworkGateway.shared.entries() }
        }
    }
    public func stop() { task?.cancel() }
    var shown: [LedgerEntry] { (meetingID == nil ? entries : entries.filter { $0.meetingID == meetingID || !$0.containsMeetingData }).reversed() }
    /// Bytes of meeting text/audio that went to any other host.
    public var meetingBytes: Int { entries.filter { $0.containsMeetingData && (meetingID == nil || $0.meetingID == meetingID) }.reduce(0) { $0 + $1.bytesSent } }
    public var hosts: [String] { Array(Set(entries.filter { $0.containsMeetingData && (meetingID == nil || $0.meetingID == meetingID) }.map(\.host))).sorted() }
}

public struct LedgerView: View {
    @ObservedObject var m: LedgerModel
    public init(model: LedgerModel) { m = model }
    public var body: some View {
        VStack(spacing: 0) {
            banner.padding()
            Table(m.shown) {
                TableColumn("Time") { Text($0.time.formatted(date: .omitted, time: .standard)).font(.system(.caption, design: .monospaced)) }.width(80)
                TableColumn("Host") { Text($0.host) }
                TableColumn("Sent") { Text(Self.bytes($0.bytesSent)) }.width(70)
                TableColumn("Received") { Text(Self.bytes($0.bytesReceived)) }.width(70)
                TableColumn("Why") { Text($0.purpose) }
                TableColumn("Provider") { Text($0.provider) }.width(110)
                TableColumn("Meeting data?") { Text($0.containsMeetingData ? "Yes" : "No") }.width(90)
            }
            .scrollContentBackground(.hidden)
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous).strokeBorder(Tokens.cyan.color.opacity(0.35), lineWidth: 1).allowsHitTesting(false))
            .padding([.horizontal, .bottom])
            .accessibilityLabel("Network requests")
            if m.shown.isEmpty { Text("No network requests yet.").foregroundStyle(.secondary).padding() }
        }
        .frame(minWidth: 820, minHeight: 420)
        .neonRoot()
        .onAppear { m.start() }.onDisappear { m.stop() }
    }

    @ViewBuilder var banner: some View {
        let zero = m.meetingBytes == 0
        HStack(spacing: 12) {
            Image(systemName: zero ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                .font(.title).foregroundStyle(zero ? Tokens.mint.color : Tokens.red.color).accessibilityHidden(true)
            VStack(alignment: .leading) {
                Text(zero ? "Nothing left your Mac in this meeting" : "Meeting text was sent to: \(m.hosts.joined(separator: ", "))")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                Text("Meeting data sent: \(Self.bytes(m.meetingBytes))").font(.system(.callout, design: .monospaced))
            }
            Spacer()
        }
        .padding(14).neonCard(zero ? Tokens.mint.color : Tokens.red.color)
        .accessibilityElement(children: .combine)
    }
    static func bytes(_ n: Int) -> String { n == 0 ? "0 bytes" : ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .file) }
}

extension LedgerEntry: @retroactive Hashable { public func hash(into h: inout Hasher) { h.combine(id) } }
