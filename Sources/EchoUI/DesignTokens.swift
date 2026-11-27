import SwiftUI
import AppKit

/// Single source of truth for Chitter's "Neon Night" theme.
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
    // "Neon Night": true black surfaces with neon accents. Dark only.
    public static let black = Hex(0x000000), surface = Hex(0x0B0B12), raised = Hex(0x15151F)
    public static let text = Hex(0xF4F6FF), textDim = Hex(0xA9AFCB)
    /// Primary actions and focus.
    public static let cyan = Hex(0x00E5FF)
    /// Highlights, including the pulled thread from a note to its source line.
    public static let magenta = Hex(0xFF2BD6)
    /// Translated text and "healthy".
    public static let mint = Hex(0x3DFFA8)
    public static let yellow = Hex(0xFFE600), red = Hex(0xFF3B6B), violet = Hex(0xA66BFF), orange = Hex(0xFF8A1F)

    /// Speaker thread order. Never rely on colour alone: pair with `speakerInitial`.
    public static let speakerThreads: [Hex] = [cyan, magenta, mint, yellow, violet, orange]
    public static func thread(_ speaker: Int) -> Hex { speakerThreads[((speaker % 6) + 6) % 6] }

    /// Corner radii. Everything Chitter draws is rounded; controls are fully rounded capsules.
    public enum Radius { public static let small: CGFloat = 12, card: CGFloat = 18, panel: CGFloat = 24 }
    public static func speakerInitial(_ speaker: Int) -> String { String(UnicodeScalar(UInt8(65 + ((speaker % 26) + 26) % 26))) }
}

/// F17: windows that show meeting content are hidden from screen sharing / recording by default.
public enum ScreenShareSafety {
    public static func apply(to window: NSWindow, hidden: Bool) { window.sharingType = hidden ? .none : .readOnly }
}
