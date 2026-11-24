import SwiftUI
import EchoCore
import EchoNotes

// MARK: anchors for the thread
struct ThreadAnchors: Equatable {
    var lines: [Int: Anchor<CGRect>] = [:]
    var items: [String: Anchor<CGRect>] = [:]
}
struct ThreadKey: PreferenceKey {
    static let defaultValue = ThreadAnchors()
    static func reduce(value: inout ThreadAnchors, nextValue: () -> ThreadAnchors) {
        let n = nextValue(); value.lines.merge(n.lines) { $1 }; value.items.merge(n.items) { $1 }
    }
}

public struct NotesView: View {
    @ObservedObject var vm: NotesViewModel
    @FocusState private var searchFocused: Bool
    @Environment(\.colorScheme) private var scheme
    public init(vm: NotesViewModel) { self.vm = vm }

    var bg: Color { scheme == .dark ? Tokens.ink.color : Tokens.linen.color }
    var surface: Color { scheme == .dark ? Tokens.woad.color : Tokens.bone.color }
    var fg: Color { scheme == .dark ? Tokens.textLight.color : Tokens.textDark.color }

    public var body: some View {
        HStack(spacing: 0) {
            Spool(vm: vm, searchFocused: $searchFocused, surface: surface, fg: fg).frame(width: 230)
            Divider()
            HStack(spacing: 0) {
                Warp(vm: vm, fg: fg, surface: surface)
                Divider()
                Weft(vm: vm, fg: fg, surface: surface).frame(width: 360)
            }
            .overlayPreferenceValue(ThreadKey.self) { a in
                GeometryReader { geo in ThreadOverlay(vm: vm, anchors: a, geo: geo) }.allowsHitTesting(false)
            }
        }
        .background(bg)
        .frame(minWidth: 1000, minHeight: 600)
        .background(Button("Find") { searchFocused = true }.keyboardShortcut("f", modifiers: .command).opacity(0).accessibilityHidden(true))
        .onAppear { vm.startAutoRefresh(); vm.refreshEngineLabel() }
        .onDisappear { vm.stopAutoRefresh() }
    }
}

// MARK: Spool (left)
struct Spool: View {
    @ObservedObject var vm: NotesViewModel
    var searchFocused: FocusState<Bool>.Binding
    let surface: Color, fg: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Search all meetings", text: $vm.searchText)
                .textFieldStyle(.roundedBorder)
                .focused(searchFocused)
                .accessibilityLabel("Search all meetings")
            if !vm.hits.isEmpty {
                Text("\(vm.hits.count) matches").font(.caption).foregroundStyle(fg.opacity(0.7))
                List(vm.hits.indices, id: \.self) { i in
                    let h = vm.hits[i]
                    Button { vm.open(hit: h) } label: {
                        VStack(alignment: .leading) {
                            Text(h.text).lineLimit(2).font(.callout)
                            Text("\(h.meetingID.prefix(10)) · L\(h.lineID)\(h.fuzzy ? " · close match" : "")").font(.caption2).foregroundStyle(.secondary)
                        }
                    }.buttonStyle(.plain).accessibilityLabel("Match in line \(h.lineID): \(h.text)")
                }.listStyle(.plain)
            } else {
                Text("Meetings").font(.headline).foregroundStyle(fg)
                List(selection: $vm.selectedID) {
                    ForEach(vm.meetings, id: \.id) { m in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.title).font(.system(.body, design: .serif))
                            Text(m.startedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                        }.tag(m.id as String?).accessibilityElement(children: .combine)
                    }
                }.listStyle(.sidebar)
            }
        }
        .padding(12)
        .background(surface)
    }
}

// MARK: Warp (transcript)
struct Warp: View {
    @ObservedObject var vm: NotesViewModel
    let fg: Color, surface: Color
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if vm.segments.isEmpty {
                        Text("Nothing here yet. Start listening with ⌃⌥R, or play the sample from the menu.")
                            .foregroundStyle(fg.opacity(0.7)).padding(24)
                    }
                    ForEach(vm.segments) { s in
                        WarpRow(seg: s, active: vm.activeLines.contains(s.id), fg: fg, big: vm.accessibilityMode)
                            .id(s.id)
                            .anchorPreference(key: ThreadKey.self, value: .bounds) { ThreadAnchors(lines: [s.id: $0]) }
                    }
                }.padding(.vertical, 12)
            }
            .onChange(of: vm.scrollTarget) { _, target in
                guard let target else { return }
                withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(target, anchor: .center) }
                vm.scrollTarget = nil
            }
        }
        .accessibilityLabel("Transcript")
    }
}

struct WarpRow: View {
    let seg: Segment, active: Bool, fg: Color, big: Bool
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let thread = Tokens.thread(seg.speaker)
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 2) {   // the speaker "thread" gutter (shape + colour, never colour alone)
                Text(Tokens.speakerInitial(seg.speaker)).font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(Tokens.ink.color).frame(width: 18, height: 18).background(Circle().fill(thread.color))
                Rectangle().fill(thread.color).frame(width: 3)
            }.frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("L\(seg.id)").font(.system(.caption, design: .monospaced)).foregroundStyle(fg.opacity(0.6))
                    Text(Exporter.timeLabel(seg.start)).font(.system(.caption, design: .monospaced)).foregroundStyle(fg.opacity(0.5))
                }
                Text(seg.text).font(.system(size: big ? 22 : 14))
                    .underline(seg.confidence.map { $0 < 0.6 } ?? false, pattern: .dot, color: Tokens.madder.color)
                    .foregroundStyle(fg)
                if let t = seg.translation, !t.isEmpty {
                    Text(t).font(.system(size: big ? 22 : 14, design: .serif)).foregroundStyle(Tokens.translationText(dark: scheme == .dark).color)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
        .background(active ? Tokens.weld.color.opacity(0.28) : Color.clear)
        .overlay(alignment: .leading) { if active { Rectangle().fill(Tokens.weld.color).frame(width: 3) } }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Line \(seg.id), speaker \(Tokens.speakerInitial(seg.speaker)): \(seg.text)")
    }
}

extension Exporter { static func timeLabel(_ t: TimeInterval) -> String { String(format: "%02d:%02d", Int(t) / 60, Int(t) % 60) } }

// MARK: Weft (notes)
struct Weft: View {
    @ObservedObject var vm: NotesViewModel
    let fg: Color, surface: Color
    @FocusState private var focused: String?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Button(vm.isGenerating ? "Writing notes…" : "Write notes") { vm.generateNotes() }
                        .disabled(vm.isGenerating || vm.segments.isEmpty).keyboardShortcut("g", modifiers: .command)
                        .accessibilityHint("Creates a summary, decisions and action items from the transcript")
                    Button("Copy as Markdown") {
                        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(vm.markdown(), forType: .string)
                    }.accessibilityLabel("Copy meeting as Markdown")
                    Menu("Export") {
                        Button("Markdown…") { Exports.save(vm, .markdown) }
                        Button("Subtitles (SRT)…") { Exports.save(vm, .srt) }
                        Button("Word (DOCX)…") { Exports.save(vm, .docx) }
                    }.accessibilityLabel("Export meeting")
                }
                if !vm.engineName.isEmpty { Text("Notes engine: \(vm.engineName)").font(.caption).foregroundStyle(fg.opacity(0.65)) }
                if let n = vm.notes, !n.isEmpty {
                    if !n.summary.isEmpty { section("Summary") { Text(n.summary).font(.system(.body, design: .serif)).foregroundStyle(fg) } }
                    if !n.decisions.isEmpty {
                        section("Decisions") { ForEach(Array(n.decisions.enumerated()), id: \.offset) { i, d in
                            item(id: "d\(i)", text: d.text, lines: d.lines, meta: nil) } }
                    }
                    if !n.actions.isEmpty {
                        section("Action items") { ForEach(Array(n.actions.enumerated()), id: \.offset) { i, a in
                            item(id: "a\(i)", text: a.text, lines: a.lines, meta: [a.owner, a.due.map { "due \($0)" }].compactMap { $0 }.joined(separator: " · ")) } }
                    }
                    if !n.topics.isEmpty { section("Topics") { Text(n.topics.joined(separator: " · ")).foregroundStyle(fg) } }
                    if !n.glossary.isEmpty { section("Glossary") { ForEach(n.glossary, id: \.term) { g in
                        (Text(g.term).bold() + Text(" — \(g.meaning)")).foregroundStyle(fg).font(.callout) } } }
                } else {
                    Text("No notes yet. “Write notes” turns the transcript into a summary, decisions and action items. Hover one to pull its thread to the source line.")
                        .foregroundStyle(fg.opacity(0.7)).font(.callout)
                }
            }.padding(16)
        }
        .background(surface.opacity(0.5))
        .onChange(of: focused) { _, f in    // keyboard users get the same thread as hover
            guard let f else { if !vm.pinned { vm.hover(nil) }; return }
            vm.hover(linesFor(f))
        }
    }

    func linesFor(_ id: String) -> [Int]? {
        guard let n = vm.notes, let i = Int(id.dropFirst()) else { return nil }
        return id.hasPrefix("d") ? (i < n.decisions.count ? n.decisions[i].lines : nil) : (i < n.actions.count ? n.actions[i].lines : nil)
    }

    func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(.title3, design: .serif).weight(.semibold)).foregroundStyle(fg).accessibilityAddTraits(.isHeader)
            content()
        }
    }

    func item(id: String, text: String, lines: [Int], meta: String?) -> some View {
        Button { vm.click(lines) } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(text).multilineTextAlignment(.leading).foregroundStyle(fg)
                HStack(spacing: 6) {
                    if let meta, !meta.isEmpty { Text(meta).font(.caption).foregroundStyle(Tokens.translationText(dark: scheme == .dark).color) }
                    Text(lines.map { "L\($0)" }.joined(separator: " ")).font(.system(.caption2, design: .monospaced)).foregroundStyle(fg.opacity(0.55))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(vm.activeLines == lines ? Tokens.weld.color.opacity(0.25) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($focused, equals: id)
        .onHover { inside in inside ? vm.hover(lines) : vm.hover(nil) }
        .anchorPreference(key: ThreadKey.self, value: .bounds) { ThreadAnchors(items: [id: $0]) }
        .accessibilityLabel("\(text). Supported by line \(lines.map(String.init).joined(separator: ", "))")
        .accessibilityHint("Shows the source line in the transcript")
        .contextMenu { Button("Clear highlight") { vm.clearPin() } }
    }
}

// MARK: the pulled thread
struct ThreadOverlay: View {
    @ObservedObject var vm: NotesViewModel
    let anchors: ThreadAnchors
    let geo: GeometryProxy
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var progress: CGFloat { vm.threadProgress }

    var activeItemID: String? {
        guard let n = vm.notes, !vm.activeLines.isEmpty else { return nil }
        if let i = n.decisions.firstIndex(where: { $0.lines == vm.activeLines }) { return "d\(i)" }
        if let i = n.actions.firstIndex(where: { $0.lines == vm.activeLines }) { return "a\(i)" }
        return nil
    }

    var body: some View {
        ZStack {
            if let id = activeItemID, let item = anchors.items[id].map({ geo[$0] }) {
                ForEach(vm.activeLines, id: \.self) { line in
                    if let a = anchors.lines[line] {
                        let r = geo[a]
                        ThreadShape(from: CGPoint(x: item.minX, y: item.midY), to: CGPoint(x: r.maxX - 6, y: r.midY))
                            .trim(from: 0, to: progress)
                            .stroke(Tokens.weld.color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .shadow(color: Tokens.weld.color.opacity(0.5), radius: 2)
                    }
                }
            }
        }
        .onChange(of: vm.activeLines) { _, new in
            guard !new.isEmpty else { return }
            if reduceMotion { vm.threadProgress = 1 }                       // Reduced Motion: instant highlight, no animation
            else { vm.threadProgress = 0; withAnimation(.easeOut(duration: 0.25)) { vm.threadProgress = 1 } }   // 250 ms ease-out (spec §4.5)
        }
    }
}

struct ThreadShape: Shape {
    var from: CGPoint, to: CGPoint
    func path(in rect: CGRect) -> Path {
        var p = Path(); p.move(to: from)
        let dx = max(60, abs(from.x - to.x) * 0.5)
        p.addCurve(to: to, control1: CGPoint(x: from.x - dx, y: from.y), control2: CGPoint(x: to.x + dx, y: to.y))
        return p
    }
}
