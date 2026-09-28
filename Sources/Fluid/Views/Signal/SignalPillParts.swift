import AppKit
import SwiftUI

/// The record square beside the timer: solid while listening, a 1.5 pt outline once input is
/// closed, and nothing (its 6 pt still reserved) when delivered or on a card.
enum SignalRecordMark: Equatable {
    case recording
    case closed
    case none
}

/// The trace row (DESIGN.md §4, §11): the target-app icon, the trace, then the record square and
/// the mono timer right-aligned in a box reserved for "99:59", all centred on the trace's
/// midline. The icon keeps the shape the OS gives it; its frame is reserved with no icon.
struct SignalTraceRow: View {
    let geometry: SignalOverlayGeometry
    let icon: NSImage?
    let trace: SignalTraceModel
    let isLive: Bool
    let isSweeping: Bool
    let mark: SignalRecordMark
    /// The running timer's start while listening; nil shows `frozenTimer`.
    let timerStart: Date?
    let frozenTimer: String

    @Environment(\.signalPalette) private var palette

    var body: some View {
        let metrics = SignalTheme.Metrics.self
        HStack(alignment: .top, spacing: 0) {
            Group {
                if let icon = self.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                } else {
                    Color.clear
                }
            }
            .frame(width: metrics.targetIcon, height: metrics.targetIcon)
            .padding(.top, metrics.traceMidline - metrics.targetIcon / 2)
            .help("Dictation target app")

            Spacer(minLength: 0)

            SignalTraceView(model: self.trace, isLive: self.isLive, isSweeping: self.isSweeping)

            Spacer(minLength: 0)

            HStack(spacing: metrics.readoutGap) {
                self.recordSquare
                self.timer
                    .frame(width: metrics.timerBoxWidth, alignment: .trailing)
            }
            .frame(height: SignalTheme.Typography.timer.lineHeight)
            .padding(.top, metrics.traceMidline - SignalTheme.Typography.timer.lineHeight / 2)
        }
        .frame(width: self.geometry.innerWidth, height: metrics.traceRowHeight, alignment: .top)
    }

    @ViewBuilder
    private var recordSquare: some View {
        let size = SignalTheme.Metrics.recordSquare
        switch self.mark {
        case .recording:
            Rectangle().fill(self.palette.accent).frame(width: size, height: size)
        case .closed:
            Rectangle()
                .strokeBorder(self.palette.accent, lineWidth: SignalTheme.Metrics.recordSquareOutline)
                .frame(width: size, height: size)
        case .none:
            Color.clear.frame(width: size, height: size)
        }
    }

    @ViewBuilder
    private var timer: some View {
        if let start = self.timerStart {
            TimelineView(.periodic(from: start, by: 1)) { context in
                self.timerText(SignalOverlayModel.formatDuration(context.date.timeIntervalSince(start)))
            }
        } else {
            self.timerText(self.frozenTimer)
        }
    }

    private func timerText(_ text: String) -> some View {
        Text(text)
            .font(SignalTheme.Typography.timer.font)
            .monospacedDigit()
            .foregroundStyle(self.palette.text)
            .lineLimit(1)
            .accessibilityLabel("Recording length \(text)")
    }
}

/// The microphone, mono uppercase, bottom-centre, the same in every visible state.
struct SignalMicRow: View {
    let text: String
    @Environment(\.signalPalette) private var palette

    var body: some View {
        SignalMonoLabel(text: self.text, role: SignalTheme.Typography.micLabel, color: self.palette.text2)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity)
            .frame(height: SignalTheme.Metrics.micRowHeight)
            .help("Microphone")
    }
}

/// The live preview: SF Pro 13.5 medium on an 18 pt line, head-truncated so the newest words stay
/// visible; dimmed and frozen while transcribing.
struct SignalPreview: View {
    let text: String
    let lines: Int
    let height: CGFloat
    let width: CGFloat
    let isDimmed: Bool
    @Environment(\.signalPalette) private var palette

    var body: some View {
        let role = SignalTheme.Typography.preview
        Text(self.text)
            .signalType(role)
            .foregroundStyle(self.isDimmed ? self.palette.textDim : self.palette.text)
            .multilineTextAlignment(.leading)
            .lineLimit(self.lines)
            .truncationMode(.head)
            .fixedSize(horizontal: false, vertical: true)
            // CSS centres each line in its 18 pt box: half the extra leading sits above line one.
            .padding(.top, role.lineSpacing / 2)
            .frame(width: self.width, height: self.height, alignment: .topLeading)
            .clipped()
    }
}

/// Delivered: the orange stamp, the headline, and the word count, in place of the preview.
struct SignalDeliveredStatement: View {
    let delivery: SignalDelivery
    @Environment(\.signalPalette) private var palette

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(self.palette.onAccent)
                .frame(width: SignalTheme.Metrics.deliveredStamp, height: SignalTheme.Metrics.deliveredStamp)
                .background(self.palette.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text(self.delivery.headline)
                    .font(SignalTheme.Typography.deliveredHeadline.font)
                    .foregroundStyle(self.palette.text)
                    .lineLimit(1)
                    .frame(height: SignalTheme.Typography.deliveredHeadline.lineHeight)
                SignalMonoLabel(text: self.delivery.meta, color: self.palette.text2)
                    .frame(height: 14)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// A rail: 30 pt chips in three slots, top at the pill's top corner, bottom at its bottom
/// corner, the middle slot centred between them (reserved, so nothing shifts).
struct SignalRail<Top: View, Middle: View, Bottom: View>: View {
    let height: CGFloat
    @ViewBuilder let top: Top
    @ViewBuilder let middle: Middle
    @ViewBuilder let bottom: Bottom

    var body: some View {
        VStack(spacing: 0) {
            self.top
            Spacer(minLength: 0)
            self.middle
                .frame(width: SignalTheme.Metrics.chip, height: SignalTheme.Metrics.chip)
            Spacer(minLength: 0)
            self.bottom
        }
        .frame(width: SignalTheme.Metrics.chip, height: self.height)
    }
}
