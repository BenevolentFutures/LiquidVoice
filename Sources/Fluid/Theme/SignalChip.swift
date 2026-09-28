import SwiftUI

/// A rail chip (DESIGN.md §4, §7, §9): 30 x 30, square, a solid fill with no edge at rest (the
/// fill keeps the glyph legible over a busy terminal). Hover draws its own bracket outside it;
/// press or latch inverts it to a solid square with a 1 pt surface keyline, shown for at least
/// 60 ms; a copy confirmation fills it orange with a check. Disabled chips dim and never
/// disappear, so nothing beside them moves.
struct SignalChip: View {
    let systemName: String
    let help: String
    /// Disabled: dimmed glyph, no hover, no press.
    var isEnabled = true
    /// Inert: looks at rest but takes no action, hover or press (the delivered hold).
    var isInert = false
    /// Latched: inverted while the thing it opened is open (History while its card is up).
    var isLatched = false
    /// The copy confirmation: orange with a check.
    var isConfirming = false
    var onHoverChanged: (Bool) -> Void = { _ in }
    let action: () -> Void

    @Environment(\.signalPalette) private var palette
    @State private var isHovered = false

    private var isLive: Bool {
        self.isEnabled && !self.isInert
    }

    var body: some View {
        Button(action: self.action) {
            Image(systemName: self.systemName)
                .font(.system(size: SignalTheme.Metrics.chipGlyphSize, weight: .semibold))
        }
        .buttonStyle(SignalChipButtonStyle(
            isEnabled: self.isEnabled,
            isLatched: self.isLatched,
            isConfirming: self.isConfirming,
            palette: self.palette
        ))
        .disabled(!self.isLive)
        .signalBracket(.chip, visible: self.isHovered && self.isLive)
        .onHover { hovering in
            let hovering = hovering && self.isLive
            guard hovering != self.isHovered else { return }
            self.isHovered = hovering
            self.onHoverChanged(hovering)
        }
        .onChange(of: self.isLive) { _, live in
            // A chip that stops being live under the pointer never gets its hover-out.
            if !live, self.isHovered {
                self.isHovered = false
                self.onHoverChanged(false)
            }
        }
        .help(self.help)
        .accessibilityLabel(self.help)
    }
}

private struct SignalChipButtonStyle: ButtonStyle {
    let isEnabled: Bool
    let isLatched: Bool
    let isConfirming: Bool
    let palette: SignalTheme.Palette

    func makeBody(configuration: Configuration) -> some View {
        SignalChipFace(
            label: configuration.label,
            isPressed: configuration.isPressed,
            isEnabled: self.isEnabled,
            isLatched: self.isLatched,
            isConfirming: self.isConfirming,
            palette: self.palette
        )
    }
}

/// The chip's face. Keeps a press visible for at least `Motion.chipPress`, so a fast click
/// still reads.
private struct SignalChipFace<Label: View>: View {
    let label: Label
    let isPressed: Bool
    let isEnabled: Bool
    let isLatched: Bool
    let isConfirming: Bool
    let palette: SignalTheme.Palette

    @State private var showsPress = false
    @State private var pressStartedAt: Date?

    private var isInverted: Bool {
        !self.isConfirming && (self.showsPress || self.isLatched)
    }

    private var fill: Color {
        if self.isConfirming { return self.palette.accent }
        return self.isInverted ? self.palette.invBackground : self.palette.chip
    }

    private var glyphColor: Color {
        if self.isConfirming { return self.palette.onAccent }
        if self.isInverted { return self.palette.invForeground }
        return self.isEnabled ? self.palette.glyph : self.palette.glyphOff
    }

    var body: some View {
        ZStack {
            if self.isConfirming {
                Image(systemName: "checkmark")
                    .font(.system(size: SignalTheme.Metrics.chipGlyphSize, weight: .semibold))
            } else {
                self.label
            }
        }
        .foregroundStyle(self.glyphColor)
        .frame(width: SignalTheme.Metrics.chip, height: SignalTheme.Metrics.chip)
        .background(self.fill)
        // The keyline keeps an inverted chip's shape over any backdrop (a black key over a black
        // terminal would otherwise vanish). Outside the chip, like the prototype's box-shadow.
        .overlay {
            Rectangle()
                .stroke(self.palette.surface, lineWidth: 1)
                .padding(-0.5)
                .opacity(self.isInverted ? 1 : 0)
                .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .animation(.linear(duration: SignalTheme.Motion.chipPress), value: self.isInverted)
        .animation(.linear(duration: SignalTheme.Motion.chipPress), value: self.isConfirming)
        .onChange(of: self.isPressed) { _, pressed in
            if pressed {
                self.pressStartedAt = Date()
                self.showsPress = true
            } else {
                let shown = self.pressStartedAt.map { Date().timeIntervalSince($0) } ?? SignalTheme.Motion.chipPress
                let remaining = max(0, SignalTheme.Motion.chipPress - shown)
                DispatchQueue.main.asyncAfter(deadline: .now() + remaining) {
                    self.showsPress = false
                }
            }
        }
    }
}
