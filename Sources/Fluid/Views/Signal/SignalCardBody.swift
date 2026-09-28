import SwiftUI

/// What a card in the grown pill says (DESIGN.md §9 state 5). The failed-delivery card is the
/// designed one; the timeout, "back", refused and microphone cards reuse its grammar and are
/// provisional, awaiting round 5.
struct SignalCardContent: Equatable {
    enum PrimaryAction: Equatable {
        case copy
        case reprocess
        case openSettings
        case none

        var title: String {
            switch self {
            case .copy: "Copy"
            case .reprocess: "Reprocess"
            case .openSettings: "Open Settings"
            case .none: ""
            }
        }

        var width: CGFloat {
            self == .openSettings ? 112 : SignalTheme.Metrics.copyButtonWidth
        }
    }

    let headline: String
    /// The transcript (quoted as said) or, for a card without one, the message.
    let body: String
    /// Where the transcript is now, or what to do next. Secondary text on the body's last line.
    let detail: String
    let primary: PrimaryAction
    /// "118 WORDS" for a transcript; empty otherwise.
    let meta: String
    /// The orange 2 pt top rule marks a failure; the "Speech recognition is back" notice has none.
    let marksFailure: Bool
}

/// The grown part of the pill: headline, body, then Copy / Dismiss / meta. 115 pt tall, the 54 pt
/// preview area plus the 61 pt growth, so the rows below it never move.
struct SignalCardBody: View {
    let content: SignalCardContent
    let onPrimary: () -> Void
    let onDismiss: () -> Void

    @Environment(\.signalPalette) private var palette
    @State private var isConfirming = false

    static let height: CGFloat = 54 + SignalTheme.Metrics.failedGrowth

    var body: some View {
        let transcript = SignalTheme.Typography.transcript
        VStack(alignment: .leading, spacing: 0) {
            Text(self.content.headline)
                .font(SignalTheme.Typography.failedHeadline.font)
                .foregroundStyle(self.palette.text)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(height: SignalTheme.Typography.failedHeadline.lineHeight, alignment: .leading)

            // Three 17 pt lines: the body clamped to two, then the detail, so the card's size never
            // depends on the transcript (provisional: DESIGN.md shows three transcript lines).
            VStack(alignment: .leading, spacing: 0) {
                Text(self.content.body)
                    .signalType(transcript)
                    .foregroundStyle(self.palette.text)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, transcript.lineSpacing / 2)
                    .frame(height: 2 * transcript.lineHeight, alignment: .topLeading)
                Text(self.content.detail)
                    .font(transcript.font)
                    .foregroundStyle(self.palette.text2)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(height: transcript.lineHeight, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 6)

            HStack(spacing: 16) {
                if self.content.primary != .none {
                    Button(action: self.primary) {
                        ZStack {
                            Text(self.content.primary.title).opacity(self.isConfirming ? 0 : 1)
                            HStack(spacing: 5) {
                                Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
                                Text("Copied")
                            }
                            .opacity(self.isConfirming ? 1 : 0)
                        }
                    }
                    .buttonStyle(SignalPrimaryButtonStyle(width: self.content.primary.width))
                    .help(self.content.primary == .copy ? "Copy the transcription to the clipboard" : self.content.primary.title)
                }
                Button("Dismiss", action: self.onDismiss)
                    .buttonStyle(SignalTextButtonStyle())
                Spacer(minLength: 0)
                if !self.content.meta.isEmpty {
                    SignalMonoLabel(text: self.content.meta, color: self.palette.text2)
                }
            }
            .frame(height: SignalTheme.Metrics.buttonHeight)
            .padding(.top, 12)
        }
        .frame(height: Self.height, alignment: .top)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(self.content.headline)
    }

    private func primary() {
        guard !self.isConfirming else { return }
        if self.content.primary == .copy {
            self.isConfirming = true
        }
        self.onPrimary()
    }
}

/// The AI-enhancement failure, in the preview area (provisional, awaiting round 5): the message,
/// then Try Again (orange, when it can retry) and Dismiss. 54 pt, like the preview it replaces.
struct SignalNoticeRow: View {
    let message: String
    let canRetry: Bool
    let onRetry: () -> Void
    let onDismiss: () -> Void
    @Environment(\.signalPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(self.message)
                .font(SignalTheme.Typography.failedHeadline.font)
                .foregroundStyle(self.palette.text)
                .lineLimit(1)
                .frame(height: SignalTheme.Typography.failedHeadline.lineHeight)
            HStack(spacing: 16) {
                if self.canRetry {
                    Button("Try Again", action: self.onRetry)
                        .buttonStyle(SignalPrimaryButtonStyle())
                }
                Button("Dismiss", action: self.onDismiss)
                    .buttonStyle(SignalTextButtonStyle())
            }
            .frame(height: SignalTheme.Metrics.buttonHeight)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
