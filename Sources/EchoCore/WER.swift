import Foundation

public enum WER {
    /// Lowercased word tokens; CJK characters count as one token each.
    public static func tokens(_ s: String) -> [String] {
        var out: [String] = [], cur = ""
        func flush() { if !cur.isEmpty { out.append(cur); cur = "" } }
        for ch in s.lowercased() {
            if ch.isLetter || ch.isNumber {
                if ch.unicodeScalars.contains(where: { (0x3040...0x30FF).contains($0.value) || (0x4E00...0x9FFF).contains($0.value) }) {
                    flush(); out.append(String(ch))
                } else { cur.append(ch) }
            } else if ch == "'" || ch == "’" { continue } else { flush() }
        }
        flush(); return out
    }
    /// Word (or CJK-character) error rate via Levenshtein distance.
    public static func rate(reference: String, hypothesis: String) -> Double {
        let r = tokens(reference), h = tokens(hypothesis)
        if r.isEmpty { return h.isEmpty ? 0 : 1 }
        var prev = Array(0...h.count)
        for i in 1...r.count {
            var cur = [i] + [Int](repeating: 0, count: h.count)
            if h.count > 0 { for j in 1...h.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (r[i - 1] == h[j - 1] ? 0 : 1))
            } }
            prev = cur
        }
        return Double(prev[h.count]) / Double(r.count)
    }
}
