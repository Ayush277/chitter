import SwiftUI
import AppKit

/// Single source of truth for Chitter's "Dyer's Palette" (spec §4.3).
public enum Tokens {
    public struct Hex { public let r, g, b: Double
        public init(_ v: UInt32) { r = Double((v >> 16) & 255) / 255; g = Double((v >> 8) & 255) / 255; b = Double(v & 255) / 255 }
        public var color: Color { Color(.sRGB, red: r, green: g, blue: b) }
        public var nsColor: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: 1) }
        /// WCAG relative luminance.
        public var luminance: Double {
            func f(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
            return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b)
        }
        public func contrast(with o: Hex) -> Double {
            let a = max(luminance, o.luminance), b = min(luminance, o.luminance)
            return (a + 0.05) / (b + 0.05)
        }
    }
    public static let ink = Hex(0x14162B), woad = Hex(0x1F2447)
    public static let linen = Hex(0xF3EDE2), bone = Hex(0xE6DDCC)
    public static let textDark = Hex(0x1C1B26), textLight = Hex(0xECE6D8)
    public static let madder = Hex(0xD9503F), weld = Hex(0xE9B53A), verdigris = Hex(0x31A092)   // nudged from #2E9C8E so it passes AA on woad (4.47 → ≥4.5)
    /// Verdigris darkened for text on light surfaces (linen/bone) — the base tone is only 2.9:1 there.
    public static let verdigrisDeep = Hex(0x1B6B60)
    public static func translationText(dark: Bool) -> Hex { dark ? verdigris : verdigrisDeep }
    public static let lichen = Hex(0x8FA66A), mulberry = Hex(0x8E4A7A), indigoDye = Hex(0x4A5BB8)

    /// Speaker thread order (spec §4.3). Never rely on colour alone: pair with `speakerInitial`.
    public static let speakerThreads: [Hex] = [weld, verdigris, madder, lichen, mulberry, indigoDye]
    public static func thread(_ speaker: Int) -> Hex { speakerThreads[((speaker % 6) + 6) % 6] }
    public static func speakerInitial(_ speaker: Int) -> String { String(UnicodeScalar(UInt8(65 + ((speaker % 26) + 26) % 26))) }
}

/// F17: windows that show meeting content are hidden from screen sharing / recording by default.
public enum ScreenShareSafety {
    public static func apply(to window: NSWindow, hidden: Bool) { window.sharingType = hidden ? .none : .readOnly }
}
