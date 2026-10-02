import AppKit
import SwiftUI

/// The "switched on but not working" hint under an Accessibility step or card.
///
/// `.staleGrant`: the app is still untrusted after the user came back from System Settings (or
/// it was trusted before), so macOS is probably holding an entry for an older build. Offers the
/// fix and a button straight to the Accessibility list. `.relaunch`: trusted, but the event tap
/// was refused; offers a relaunch. Renders nothing for `.none`.
struct AccessibilityRecoveryHintView: View {
    enum Tone {
        /// White on the onboarding backdrop.
        case onDark
        /// The settings and Getting Started cards.
        case themed
    }

    @Environment(\.theme) private var theme

    let hint: AccessibilityHint
    var conflictingCopies: [URL] = []
    var tone: Tone = .themed
    let openAccessibilitySettings: () -> Void
    let relaunch: () -> Void

    var body: some View {
        switch self.hint {
        case .none:
            EmptyView()
        case .staleGrant:
            self.content(
                headline: AccessibilityHintPolicy.staleGrantHeadline,
                body: AccessibilityHintPolicy.staleGrantBody,
                buttonTitle: "Open Accessibility Settings",
                buttonIcon: "arrow.up.right",
                action: self.openAccessibilitySettings
            )
        case .conflictingCopies:
            self.content(
                headline: AccessibilityHintPolicy.conflictingCopiesHeadline,
                body: AccessibilityHintPolicy.conflictingCopiesBody,
                paths: self.conflictingCopies.prefix(3).map { ConflictingAppCopyDetector.displayPath($0) },
                buttonTitle: "Show in Finder",
                buttonIcon: "folder",
                action: {
                    NSWorkspace.shared.activateFileViewerSelecting(Array(self.conflictingCopies.prefix(3)))
                },
                secondaryTitle: "Open Accessibility Settings",
                secondaryAction: self.openAccessibilitySettings
            )
        case .relaunch:
            self.content(
                headline: AccessibilityHintPolicy.relaunchHeadline,
                body: AccessibilityHintPolicy.relaunchBody,
                buttonTitle: "Relaunch MouthKeys",
                buttonIcon: "arrow.clockwise",
                action: self.relaunch
            )
        }
    }

    private func content(
        headline: String,
        body: String,
        paths: [String] = [],
        buttonTitle: String,
        buttonIcon: String,
        action: @escaping () -> Void,
        secondaryTitle: String? = nil,
        secondaryAction: (() -> Void)? = nil
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(self.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text(headline)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(self.primaryText)
                ForEach(paths, id: \.self) { path in
                    Text(path)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(self.primaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                Text(body)
                    .font(.system(size: 11.5, weight: .regular))
                    .foregroundStyle(self.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 6) {
                if self.tone == .onDark {
                    Button(action: action) {
                        Label(buttonTitle, systemImage: buttonIcon)
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(OnDarkHintButtonStyle())
                    .fixedSize()
                } else {
                    Button(action: action) {
                        Label(buttonTitle, systemImage: buttonIcon)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .fixedSize()
                }

                if let secondaryTitle, let secondaryAction {
                    Button(secondaryTitle, action: secondaryAction)
                        .buttonStyle(.plain)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(self.accent)
                        .fixedSize()
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            Rectangle()
                .fill(self.fill)
                .overlay(Rectangle().stroke(self.edge, lineWidth: 1))
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(headline) \(body)")
    }

    private var accent: Color {
        self.tone == .onDark ? FluidOnboardingLandingColors.blue : self.theme.palette.accent
    }

    private var primaryText: Color {
        self.tone == .onDark ? .white : .primary
    }

    private var secondaryText: Color {
        self.tone == .onDark ? Color.white.opacity(0.62) : .secondary
    }

    private var fill: Color {
        self.tone == .onDark ? Color.white.opacity(0.06) : self.theme.palette.cardBackground.opacity(0.6)
    }

    private var edge: Color {
        self.tone == .onDark ? Color.white.opacity(0.14) : Color.primary.opacity(0.12)
    }
}

/// White on the onboarding backdrop, where the system bordered style turns dark-on-dark.
private struct OnDarkHintButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(configuration.isPressed ? Color.black : Color.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Rectangle()
                    .fill(configuration.isPressed ? Color.white : Color.white.opacity(0.12))
                    .overlay(Rectangle().stroke(Color.white.opacity(0.35), lineWidth: 1))
            )
            .contentShape(Rectangle())
    }
}
