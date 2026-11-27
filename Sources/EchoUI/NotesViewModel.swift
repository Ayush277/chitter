import SwiftUI
import EchoCore
import EchoNotes

@MainActor
public final class NotesViewModel: ObservableObject {
    @Published public var meetings: [MeetingInfo] = []
    @Published public var selectedID: String? { didSet { if oldValue != selectedID { load() } } }
    @Published public var segments: [Segment] = []
    @Published public var notes: Notes?
    @Published public var activeLines: [Int] = []       // lines currently "pulled" by a note item
    @Published public var pinned = false                // clicked (stays highlighted) vs. hover
    @Published public var scrollTarget: Int?
    @Published public var searchText = "" { didSet { runSearch() } }
    @Published public var hits: [SearchHit] = []
    @Published public var isGenerating = false
    @Published public var engineName = ""
    @Published public var accessibilityMode = false
    @Published public var transcriptMode: SubtitleMode = .both
    @Published var threadProgress: CGFloat = 1

    public let store: MeetingStore
    public let index: SearchIndex?
    private let generate: ([Segment]) async -> NotesResult
    private let engineLabel: () async -> String
    private var refresh: Task<Void, Never>?

    public init(store: MeetingStore, index: SearchIndex?, engineLabel: @escaping () async -> String,
                generate: @escaping ([Segment]) async -> NotesResult) {
        self.store = store; self.index = index; self.generate = generate; self.engineLabel = engineLabel
        reloadList()
        selectedID = meetings.first?.id
    }

    public func reloadList() { meetings = store.list() }

    public func load() {
        guard let id = selectedID, let h = store.open(id) else { segments = []; notes = nil; return }
        segments = h.loadSegments()
        notes = (try? Data(contentsOf: h.notesJSONURL)).flatMap { try? JSONDecoder().decode(Notes.self, from: $0) }
        activeLines = []; pinned = false
    }

    /// Re-read files while a meeting is live so subtitles/notes appear as they're written.
    public func startAutoRefresh() {
        refresh?.cancel()
        refresh = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard let self else { return }
                if let id = self.selectedID, let m = self.meetings.first(where: { $0.id == id }), m.endedAt == nil { self.reloadList(); self.load() }
            }
        }
    }
    public func stopAutoRefresh() { refresh?.cancel() }

    public func generateNotes() {
        guard let id = selectedID, let h = store.open(id), !segments.isEmpty else { return }
        isGenerating = true
        let segs = segments
        Task {
            let r = await generate(segs)
            if let data = try? JSONEncoder().encode(r.notes) { h.saveNotes(json: data, markdown: NotesValidator.markdown(r.notes)) }
            self.notes = r.notes; self.isGenerating = false
            self.engineName = r.provider
        }
    }

    public func refreshEngineLabel() { Task { engineName = await engineLabel() } }

    // MARK: Pull the Thread
    public func hover(_ lines: [Int]?) { if !pinned { activeLines = lines ?? [] } }
    public func click(_ lines: [Int]) { pinned = true; activeLines = lines; scrollTarget = lines.first }
    public func clearPin() { pinned = false; activeLines = [] }

    private func runSearch() {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        hits = q.count >= 2 ? (index?.search(q) ?? []) : []
    }
    public func open(hit: SearchHit) { selectedID = hit.meetingID; scrollTarget = hit.lineID; activeLines = [hit.lineID]; pinned = true }

    public func markdown() -> String {
        guard let id = selectedID, let h = store.open(id) else { return "" }
        return Exporter.markdown(info: h.info, segments: segments, notes: notes.map(NotesValidator.markdown))
    }
}
