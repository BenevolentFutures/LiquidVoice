import SwiftUI

// Signal primitives (DESIGN.md §5–§7, §11): the selection bracket, the surface (fill, 1 px edge,
// flat 2 pt drop rule), and the card buttons. Every one is square: no corner radius anywhere.

/// Four L marks, one outside each corner of the frame it is laid over. The path runs on the
/// stroke's centreline: `inset` is how far outside the frame that centreline sits.
struct SignalBracketShape: Shape {
    /// Arm length measured from the centreline vertex.
    let arm: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let corners: [(CGPoint, CGFloat, CGFloat)] = [
            (CGPoint(x: rect.minX, y: rect.minY), 1, 1),
            (CGPoint(x: rect.maxX, y: rect.minY), -1, 1),
            (CGPoint(x: rect.minX, y: rect.maxY), 1, -1),
            (CGPoint(x: rect.maxX, y: rect.maxY), -1, -1),
        ]
        for (vertex, dx, dy) in corners {
            path.move(to: CGPoint(x: vertex.x, y: vertex.y + dy * self.arm))
            path.addLine(to: vertex)
            path.addLine(to: CGPoint(x: vertex.x + dx * self.arm, y: vertex.y))
        }
        return path
    }
}

/// The selection bracket drawn outside a box: a 1 pt knockout halo in the surface colour, then
/// the 1.5 pt ink stroke. It never changes layout or hit-testing; it fades in and out over 60 ms
/// linear (a cut under reduced motion). Its window must leave `SignalTheme.Metrics.windowInset`
/// of room around the box.
private struct SignalBracketOverlay: ViewModifier {
    let spec: SignalTheme.BracketSpec
    let isVisible: Bool
    @Environment(\.signalPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let stroke = SignalTheme.BracketSpec.stroke
        let halo = SignalTheme.BracketSpec.halo
        // The ink's inner edge sits `gap` clear of the box, so its centreline is half a stroke
        // further out; the bottom also clears the drop rule.
        let centreline = self.spec.gap + stroke / 2
        // Arms are measured from the outer vertex; the path runs on the centreline.
        let inkArm = self.spec.length - stroke / 2
        content.overlay {
            ZStack {
                SignalBracketShape(arm: inkArm + halo)
                    .stroke(self.palette.surface, style: StrokeStyle(lineWidth: stroke + 2 * halo, lineCap: .butt, lineJoin: .miter))
                SignalBracketShape(arm: inkArm)
                    .stroke(self.palette.bracket, style: StrokeStyle(lineWidth: stroke, lineCap: .butt, lineJoin: .miter))
            }
            .padding(EdgeInsets(
                top: -centreline,
                leading: -centreline,
                bottom: -(centreline + self.spec.drop),
                trailing: -centreline
            ))
            .opacity(self.isVisible ? 1 : 0)
            .animation(self.reduceMotion ? nil : .linear(duration: SignalTheme.Motion.bracketFade), value: self.isVisible)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// A Signal surface: an opaque fill, a 1 px edge drawn inside the frame, and the flat,
/// unblurred 2 pt drop rule under it.
private struct SignalSurface: ViewModifier {
    let hasEdge: Bool
    let hasDrop: Bool
    @Environment(\.signalPalette) private var palette

    func body(content: Content) -> some View {
        content.background {
            ZStack {
                if self.hasDrop {
                    Rectangle()
                        .fill(self.palette.drop)
                        .offset(y: SignalTheme.Metrics.dropRule)
                }
                Rectangle().fill(self.palette.surface)
                if self.hasEdge {
                    Rectangle().strokeBorder(self.palette.edge, lineWidth: SignalTheme.Metrics.edgeWidth)
                }
            }
        }
    }
}

extension View {
    /// A selection bracket outside this view's frame, shown only while `visible`.
    func signalBracket(_ spec: SignalTheme.BracketSpec, visible: Bool) -> some View {
        self.modifier(SignalBracketOverlay(spec: spec, isVisible: visible))
    }

    /// Fill, 1 px edge and drop rule (DESIGN.md §6: no materials).
    func signalSurface(edge: Bool = true, drop: Bool = true) -> some View {
        self.modifier(SignalSurface(hasEdge: edge, hasDrop: drop))
    }
}

// MARK: - Card buttons

/// The failed card's primary action: a solid orange 88 x 28 square ("Copy"). Its confirmation
/// ("✓ Copied") swaps in at the same width. Pressed, it inverts.
struct SignalPrimaryButtonStyle: ButtonStyle {
    var width: CGFloat = SignalTheme.Metrics.copyButtonWidth
    @Environment(\.signalPalette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SignalTheme.Typography.button.font)
            .foregroundStyle(configuration.isPressed ? self.palette.invForeground : self.palette.onAccent)
            .frame(width: self.width, height: SignalTheme.Metrics.buttonHeight)
            .background(configuration.isPressed ? self.palette.invBackground : self.palette.accent)
            .contentShape(Rectangle())
            .animation(.linear(duration: SignalTheme.Motion.chipPress), value: configuration.isPressed)
    }
}

/// A text-only action ("Dismiss"): ink, underlined on hover, orange while pressed.
struct SignalTextButtonStyle: ButtonStyle {
    @Environment(\.signalPalette) private var palette
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SignalTheme.Typography.textButton.font)
            .foregroundStyle(configuration.isPressed ? self.palette.accent : self.palette.text)
            .underline(self.isHovered, color: configuration.isPressed ? self.palette.accent : self.palette.text)
            .frame(height: SignalTheme.Metrics.buttonHeight)
            .contentShape(Rectangle())
            .onHover { self.isHovered = $0 }
    }
}

/// A mono uppercase label: every number and placard in Signal.
struct SignalMonoLabel: View {
    let text: String
    var role: SignalTheme.TypeRole = SignalTheme.Typography.meta
    var color: Color

    var body: some View {
        Text(self.text)
            .font(self.role.font)
            .tracking(self.role.tracking)
            .textCase(.uppercase)
            .foregroundStyle(self.color)
            .lineLimit(1)
    }
}
