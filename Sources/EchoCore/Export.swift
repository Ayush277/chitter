import Foundation

public enum Exporter {
    static func stamp(_ t: TimeInterval, srt: Bool = false) -> String {
        let ms = Int((t * 1000).rounded()), h = ms / 3_600_000, m = ms / 60_000 % 60, s = ms / 1000 % 60, r = ms % 1000
        return srt ? String(format: "%02d:%02d:%02d,%03d", h, m, s, r) : String(format: "%02d:%02d:%02d", h, m, s)
    }

    public static func markdown(info: MeetingInfo, segments: [Segment], notes: String? = nil) -> String {
        var out = "# \(info.title)\n\n"
        let df = DateFormatter(); df.dateStyle = .medium; df.timeStyle = .short
        out += "_\(df.string(from: info.startedAt))_\n\n"
        if let notes, !notes.isEmpty { out += notes.trimmingCharacters(in: .newlines) + "\n\n" }
        out += "## Transcript\n\n"
        for s in segments {
            out += "**[\(stamp(s.start))] \(Self.speakerLabel(s.speaker)):** \(s.text)\n"
            if let t = s.translation, !t.isEmpty { out += "> \(t)\n" }
            out += "\n"
        }
        return out
    }
    static func speakerLabel(_ n: Int) -> String { "Speaker \(String(UnicodeScalar(UInt8(65 + ((n % 26) + 26) % 26))))" }

    public static func srt(segments: [Segment], useTranslation: Bool = false) -> String {
        var out = ""; var idx = 1
        for (i, s) in segments.enumerated() {
            var start = s.start, end = s.end
            if end <= start { start = Double(i) * 3; end = start + 3 }
            let text = useTranslation ? (s.translation ?? s.text) : s.text
            out += "\(idx)\n\(stamp(start, srt: true)) --> \(stamp(end, srt: true))\n\(text)\n\n"; idx += 1
        }
        return out
    }

    // MARK: DOCX — minimal OOXML in an uncompressed zip, no third-party libraries.
    public static func docx(info: MeetingInfo, segments: [Segment], notes: String? = nil) -> Data {
        func esc(_ s: String) -> String { s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;") }
        func p(_ text: String, bold: Bool = false, size: Int? = nil) -> String {
            var rpr = ""; if bold || size != nil { rpr = "<w:rPr>\(bold ? "<w:b/>" : "")\(size.map { "<w:sz w:val=\"\($0)\"/>" } ?? "")</w:rPr>" }
            return "<w:p><w:r>\(rpr)<w:t xml:space=\"preserve\">\(esc(text))</w:t></w:r></w:p>"
        }
        var body = p(info.title, bold: true, size: 40)
        if let notes, !notes.isEmpty { for line in notes.split(separator: "\n", omittingEmptySubsequences: true) {
            let l = String(line); body += l.hasPrefix("#") ? p(l.drop(while: { $0 == "#" || $0 == " " }).description, bold: true, size: 28) : p(l)
        } }
        body += p("Transcript", bold: true, size: 28)
        for s in segments {
            body += p("[\(stamp(s.start))] \(speakerLabel(s.speaker)): \(s.text)")
            if let t = s.translation, !t.isEmpty { body += p("    \(t)") }
        }
        let doc = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:body>\(body)</w:body></w:document>"
        let ct = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/></Types>"
        let rels = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"word/document.xml\"/></Relationships>"
        var z = ZipWriter()
        z.add("[Content_Types].xml", Data(ct.utf8)); z.add("_rels/.rels", Data(rels.utf8)); z.add("word/document.xml", Data(doc.utf8))
        return z.finish()
    }
}

/// Minimal "stored" (uncompressed) zip writer.
public struct ZipWriter {
    private var out = Data(), central = Data(), count = 0
    public init() {}

    static let table: [UInt32] = (0..<256).map { i in (0..<8).reduce(UInt32(i)) { c, _ in c & 1 == 1 ? 0xEDB88320 ^ (c >> 1) : c >> 1 } }
    public static func crc32(_ d: Data) -> UInt32 { ~d.reduce(UInt32.max) { table[Int(($0 ^ UInt32($1)) & 0xFF)] ^ ($0 >> 8) } }

    private func le(_ v: UInt32, _ n: Int) -> Data { Data((0..<n).map { UInt8((v >> (8 * UInt32($0))) & 0xFF) }) }

    public mutating func add(_ name: String, _ data: Data) {
        let nameData = Data(name.utf8), crc = Self.crc32(data), offset = UInt32(out.count)
        var h = Data()
        h += le(0x04034b50, 4) + le(20, 2) + le(0x0800, 2) + le(0, 2) + le(0, 2) + le(0x21, 2)   // UTF-8 flag, stored, 1980-01-01
        h += le(crc, 4) + le(UInt32(data.count), 4) + le(UInt32(data.count), 4) + le(UInt32(nameData.count), 2) + le(0, 2)
        out += h + nameData + data
        var c = Data()
        c += le(0x02014b50, 4) + le(20, 2) + le(20, 2) + le(0x0800, 2) + le(0, 2) + le(0, 2) + le(0x21, 2)
        c += le(crc, 4) + le(UInt32(data.count), 4) + le(UInt32(data.count), 4) + le(UInt32(nameData.count), 2)
        c += le(0, 2) + le(0, 2) + le(0, 2) + le(0, 2) + le(0, 4) + le(offset, 4)
        central += c + nameData; count += 1
    }
    public mutating func finish() -> Data {
        let start = UInt32(out.count)
        var e = Data()
        e += le(0x06054b50, 4) + le(0, 2) + le(0, 2) + le(UInt32(count), 2) + le(UInt32(count), 2) + le(UInt32(central.count), 4) + le(start, 4) + le(0, 2)
        return out + central + e
    }
}
