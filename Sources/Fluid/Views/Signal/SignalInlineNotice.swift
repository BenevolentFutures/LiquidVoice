import SwiftUI

/// A notice row (DESIGN.md §15): news that needs no rescue, in the pill's reserved preview slot,
/// the way Pasted swaps in. Three 18 pt rows: the headline (Pro 13.5 semibold), the reason (Pro 13,
/// `text-2`), then inline text actions, **Reprocess** (Pro 13 semibold in `accent` with a 12 pt
/// glyph, no fill) · **Dismiss** (Pro 13 medium, `text-2`). Each action draws its own outside
/// bracket on hover, like a chip, and the pill's bracket yields; a press inverts it.
struct SignalInlineNotice: View {
    let notice: SignalNotice
    /// Holds an action's hover for renders ("notice-reprocess", "notice-dismiss").
    var isHoverForced: String?
    var onHoverChanged: (String, Bool) -> Void = { _, _ in }
    let onReprocess: () -> Void
    let onDismiss: () -> Void

    @Environment(\.signalPalette) private var palette

    static let rowHeight: CGFloat = 18

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(self.notice.headline)
                .font(SignalTheme.Typography.failedHeadline.font)
                .foregroundStyle(self.palette.text)
                .lineLimit(1)
                .frame(height: Self.rowHeight, alignment: .leading)
            Text(self.notice.reason)
                .font(SignalTheme.Typography.reason.font)
                .foregroundStyle(self.palette.text2)
                .lineLimit(1)
                .frame(height: Self.rowHeight, alignment: .leading)
            HStack(spacing: 6) {
                SignalTextAction(
                    id: "notice-reprocess",
                    title: "Reprocess",
                    systemName: "arrow.clockwise",
                    isAccent: true,
                    help: "Transcribe the kept audio",
                    isHoverForced: self.isHoverForced == "notice-reprocess",
                    onHoverChanged: self.onHoverChanged,
                    action: self.onReprocess
                )
                Text("·")
                    .font(SignalTheme.Typography.reason.font)
                    .foregroundStyle(self.palette.text2)
                    .accessibilityHidden(true)
                SignalTextAction(
                    id: "notice-dismiss",
                    title: "Dismiss",
                    help: "Dismiss",
                    isHoverForced: self.isHoverForced == "notice-dismiss",
                    onHoverChanged: self.onHoverChanged,
                    action: self.onDismiss
                )
            }
            .frame(height: Self.rowHeight)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(self.notice.headline)
    }
}

/// An inline text action: no fill at rest, a chip's outside bracket on hover, inverted while
/// pressed. Its 4 pt side padding is taken back from the layout, so the text sits where the
/// prototype puts it and the press fill still has room.
private struct SignalTextAction: View {
    let id: String
    let title: String
    var systemName: String?
    var isAccent = false
    let help: String
    var isHoverForced = false
    let onHoverChanged: (String, Bool) -> Void
    let action: () -> Void

    @Environment(\.signalPalette) private var palette
    @State private var isHovered = false

    var body: some View {
        Button(action: self.action) {
            HStack(spacing: 5) {
                if let systemName = self.systemName {
                    Image(systemName: systemName)
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(self.title)
            }
        }
        .buttonStyle(SignalTextActionStyle(isAccent: self.isAccent, palette: self.palette))
        .signalBracket(.chip, visible: self.isHovered || self.isHoverForced)
        .padding(.horizontal, -4)
        .onHover { hovering in
            guard hovering != self.isHovered else { return }
            self.isHovered = hovering
            self.onHoverChanged(self.id, hovering)
        }
        .onDisappear {
            if self.isHovered { self.onHoverChanged(self.id, false) }
        }
        .help(self.help)
        .accessibilityLabel(self.title)
    }
}

private struct SignalTextActionStyle: ButtonStyle {
    let isAccent: Bool
    let palette: SignalTheme.Palette

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .font(.system(size: 13, weight: self.isAccent ? .semibold : .medium))
            .foregroundStyle(pressed ? self.palette.invForeground : (self.isAccent ? self.palette.accent : self.palette.text2))
            .frame(height: SignalInlineNotice.rowHeight)
            .padding(.horizontal, 4)
            .background(pressed ? self.palette.invBackground : Color.clear)
            .contentShape(Rectangle())
            .signalClickTarget()
            .animation(.linear(duration: SignalTheme.Motion.chipPress), value: pressed)
    }
}
