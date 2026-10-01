import AppKit
import SwiftUI

/// One recovery card (DESIGN.md §9.5, §15): the pill grown upward with the orange 2 pt top rule,
/// a headline, one reason line (at most two), the transcript (failed cards only, 3 lines), then
/// one solid orange primary action, Dismiss, and mono meta on the right.
struct SignalCardContent: Equatable {
    enum PrimaryAction: Equatable {
        case copy
        case reprocess
        case openSystemSettings
        case none

        var title: String {
            switch self {
            case .copy: "Copy"
            case .reprocess: "Reprocess"
            case .openSystemSettings: "Open System Settings"
            case .none: ""
            }
        }

        var systemName: String {
            switch self {
            case .copy: "doc.on.doc"
            case .reprocess: "arrow.clockwise"
            case .openSystemSettings: "gearshape"
            case .none: ""
            }
        }
    }

    let headline: String
    let reason: String
    /// The transcript, for a failed paste only.
    var transcript: String?
    let primary: PrimaryAction
    /// "118 WORDS" for a transcript; empty when the frozen timer already says it all.
    var meta = ""
    /// The microphone card: the trace row shows a hollow square and a dim 0:00, and the mic row
    /// reads NO MICROPHONE.
    var isMicrophoneOff = false

    /// The reason wraps to two lines when it does not fit one at the pill's text width.
    func reasonLines(width: CGFloat) -> Int {
        let font = SignalTheme.Typography.reason.nsFont
        let size = (self.reason as NSString).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        let lineHeight = NSLayoutManager().defaultLineHeight(for: font)
        return size.height > lineHeight * 1.5 ? 2 : 1
    }

    /// The grown top area (round 6): 74 pt for a one-line card, 128 for a failed paste, 144 with a
    /// two-line reason, so the pill is 156 / 210 / 226 tall and everything below the card stays put.
    func height(width: CGFloat) -> CGFloat {
        let reason = CGFloat(self.reasonLines(width: width)) * SignalTheme.Typography.reason.lineHeight
        let transcript: CGFloat = self.transcript == nil ? 0 : 6 + 3 * SignalTheme.Typography.transcript.lineHeight
        return SignalTheme.Typography.failedHeadline.lineHeight + 4 + reason + transcript
            + SignalTheme.Metrics.cardActionsGap + SignalTheme.Metrics.buttonHeight
    }
}

/// The card's top area inside the grown pill.
struct SignalCardBody: View {
    let content: SignalCardContent
    let width: CGFloat
    let onPrimary: () -> Void
    let onDismiss: () -> Void

    @Environment(\.signalPalette) private var palette
    @State private var isConfirming = false

    var body: some View {
        let reason = SignalTheme.Typography.reason
        let transcript = SignalTheme.Typography.transcript
        VStack(alignment: .leading, spacing: 0) {
            Text(self.content.headline)
                .font(SignalTheme.Typography.failedHeadline.font)
                .foregroundStyle(self.palette.text)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(height: SignalTheme.Typography.failedHeadline.lineHeight, alignment: .leading)

            Text(self.content.reason)
                .signalType(reason)
                .foregroundStyle(self.palette.text2)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, reason.lineSpacing / 2)
                .frame(
                    width: self.width,
                    height: CGFloat(self.content.reasonLines(width: self.width)) * reason.lineHeight,
                    alignment: .topLeading
                )
                .padding(.top, 4)

            if let text = self.content.transcript {
                Text(text)
                    .signalType(transcript)
                    .foregroundStyle(self.palette.text)
                    .lineLimit(3)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, transcript.lineSpacing / 2)
                    .frame(width: self.width, height: 3 * transcript.lineHeight, alignment: .topLeading)
                    .clipped()
                    .padding(.top, 6)
            }

            HStack(spacing: 16) {
                if self.content.primary != .none {
                    Button(action: self.primary) {
                        ZStack {
                            self.primaryLabel(self.content.primary.systemName, self.content.primary.title)
                                .opacity(self.isConfirming ? 0 : 1)
                            if self.content.primary == .copy {
                                self.primaryLabel("checkmark", "Copied")
                                    .opacity(self.isConfirming ? 1 : 0)
                            }
                        }
                    }
                    .buttonStyle(SignalPrimaryButtonStyle())
                    .signalHoverBracket()
                    .help(self.primaryHelp)
                }
                Button("Dismiss", action: self.onDismiss)
                    .buttonStyle(SignalTextButtonStyle())
                    .signalHoverBracket()
                Spacer(minLength: 0)
                if !self.content.meta.isEmpty {
                    SignalMonoLabel(text: self.content.meta, color: self.palette.text2)
                }
            }
            .frame(height: SignalTheme.Metrics.buttonHeight)
            .padding(.top, SignalTheme.Metrics.cardActionsGap)
        }
        .frame(width: self.width, height: self.content.height(width: self.width), alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(self.content.headline)
    }

    private var primaryHelp: String {
        switch self.content.primary {
        case .copy: "Copy the transcription to the clipboard"
        case .reprocess: "Transcribe the kept audio again"
        case .openSystemSettings: self.content.isMicrophoneOff ? "Privacy & Security › Microphone" : "Privacy & Security › Accessibility"
        case .none: ""
        }
    }

    private func primaryLabel(_ systemName: String, _ title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
            Text(title)
        }
        .fixedSize()
    }

    private func primary() {
        guard !self.isConfirming else { return }
        if self.content.primary == .copy {
            self.isConfirming = true
            DispatchQueue.main.asyncAfter(deadline: .now() + SignalTheme.Motion.copyFeedbackButton) {
                self.isConfirming = false
            }
        }
        self.onPrimary()
    }
}

/// The AI-enhancement failure, in the preview area (provisional: DESIGN.md does not cover it): the
/// message, then Try Again (orange, when it can retry) and Dismiss. 48 pt, like the preview.
struct SignalNoticeRow: View {
    let message: String
    let canRetry: Bool
    var isCompact = false
    let onRetry: () -> Void
    let onDismiss: () -> Void
    @Environment(\.signalPalette) private var palette

    var body: some View {
        if self.isCompact {
            HStack(spacing: 12) {
                self.messageText
                Spacer(minLength: 4)
                if self.canRetry {
                    Button("Try Again", action: self.onRetry).buttonStyle(SignalTextButtonStyle()).signalHoverBracket()
                }
                Button("Dismiss", action: self.onDismiss).buttonStyle(SignalTextButtonStyle()).signalHoverBracket()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                self.messageText
                    .frame(height: SignalTheme.Typography.failedHeadline.lineHeight)
                HStack(spacing: 16) {
                    if self.canRetry {
                        Button("Try Again", action: self.onRetry)
                            .buttonStyle(SignalPrimaryButtonStyle())
                            .signalHoverBracket()
                    }
                    Button("Dismiss", action: self.onDismiss)
                        .buttonStyle(SignalTextButtonStyle())
                        .signalHoverBracket()
                }
                .frame(height: SignalTheme.Metrics.buttonHeight)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var messageText: some View {
        Text(self.message)
            .font(SignalTheme.Typography.failedHeadline.font)
            .foregroundStyle(self.palette.text)
            .lineLimit(1)
    }
}
