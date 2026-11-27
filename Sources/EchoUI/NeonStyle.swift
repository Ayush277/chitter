import SwiftUI
import AppKit

/// The shared look: black surfaces, neon edges, rounded everything.
public extension View {
    /// A rounded card with a neon edge and a soft glow.
    func neonCard(_ edge: Color = Tokens.cyan.color, radius: CGFloat = Tokens.Radius.card, fill: Color = Tokens.surface.color) -> some View {
        background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(edge.opacity(0.55), lineWidth: 1.5).allowsHitTesting(false))
            .shadow(color: edge.opacity(0.28), radius: 8)
    }
    /// A pill-shaped text field.
    func neonField(_ edge: Color = Tokens.cyan.color) -> some View {
        textFieldStyle(.plain)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule(style: .circular).fill(Tokens.raised.color))
            .overlay(Capsule(style: .circular).strokeBorder(edge.opacity(0.45), lineWidth: 1.2).allowsHitTesting(false))
    }
    /// Root styling for a whole window: black background, dark controls, cyan tint, capsule buttons.
    func neonRoot() -> some View {
        buttonStyle(NeonButtonStyle())
            .tint(Tokens.cyan.color)
            .foregroundStyle(Tokens.text.color)
            .background(Tokens.black.color)
            .preferredColorScheme(.dark)
    }
}

/// Capsule button with a neon outline; `prominent` fills it.
public struct NeonButtonStyle: ButtonStyle {
    var prominent: Bool
    var color: Color
    public init(prominent: Bool = false, color: Color = Tokens.cyan.color) { self.prominent = prominent; self.color = color }
    public func makeBody(configuration: Configuration) -> some View { Label(configuration: configuration, prominent: prominent, color: color) }
    private struct Label: View {
        let configuration: ButtonStyleConfiguration, prominent: Bool, color: Color
        @Environment(\.isEnabled) private var enabled
        var body: some View {
            configuration.label
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .padding(.horizontal, 14).padding(.vertical, 6)
                .foregroundStyle(prominent ? Tokens.black.color : Tokens.text.color)
                .background(Capsule(style: .circular).fill(prominent ? color : color.opacity(configuration.isPressed ? 0.28 : 0.10)))
                .overlay(Capsule(style: .circular).strokeBorder(color.opacity(0.8), lineWidth: 1.2))
                .shadow(color: color.opacity(enabled ? (configuration.isPressed ? 0.6 : 0.3) : 0), radius: 5)
                .opacity(enabled ? 1 : 0.4)
                .contentShape(Capsule(style: .circular))
        }
    }
}

/// A rounded segmented control. The system one can't be tinted or given capsule corners on macOS.
public struct NeonSegmented<Value: Hashable>: View {
    let label: String
    let options: [(Value, String)]
    @Binding var selection: Value
    var color: Color
    public init(_ label: String, options: [(Value, String)], selection: Binding<Value>, color: Color = Tokens.cyan.color) {
        self.label = label; self.options = options; _selection = selection; self.color = color
    }
    public var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.0) { value, title in
                let on = value == selection
                Button { selection = value } label: {
                    Text(title).font(.system(.callout, design: .rounded).weight(.semibold)).lineLimit(1).fixedSize()
                        .frame(maxWidth: .infinity).padding(.horizontal, 10).padding(.vertical, 5)
                        .foregroundStyle(on ? Tokens.black.color : Tokens.textDim.color)
                        .background(Capsule(style: .circular).fill(on ? color : Color.clear))
                        .shadow(color: on ? color.opacity(0.55) : .clear, radius: 6)
                        .contentShape(Capsule(style: .circular))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Capsule(style: .circular).fill(Tokens.raised.color))
        .overlay(Capsule(style: .circular).strokeBorder(color.opacity(0.35), lineWidth: 1).allowsHitTesting(false))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

/// Dark, black title bar to match the content.
@MainActor
public enum NeonWindow {
    public static func apply(to window: NSWindow) {
        window.appearance = NSAppearance(named: .darkAqua)
        window.titlebarAppearsTransparent = true
        window.backgroundColor = Tokens.black.nsColor
    }
}
