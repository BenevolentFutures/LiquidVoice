import Foundation
import SwiftUI

/// Onboarding step that offers optional AI polishing through the user's own provider.
struct OnboardingAIEnhancementStepView: View {
    let progressValue: Double
    let glowCenter: UnitPoint
    let isRunning: Bool
    let isRecordingShortcut: Bool
    let onGlowMove: (CGPoint, CGSize) -> Void
    let onGlowExit: () -> Void
    let onBack: () -> Void
    let onSkip: () -> Void
    let onUseAIProvider: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var hoveredButtonID: String?

    private struct EnhancementExample: Identifiable {
        let id: String
        let raw: String
        let polished: String
    }

    private enum ButtonTone {
        case primary
        case secondary
    }

    private struct PillButtonConfiguration {
        let id: String
        let title: String
        let systemImage: String?
        let tone: ButtonTone
        let width: CGFloat
        let height: CGFloat
        let fontSize: CGFloat
        let isEnabled: Bool
    }

    private enum ExampleGridMetrics {
        static let widthInset: CGFloat = 88
        static let maxWidth: CGFloat = 900
        static let headerLeadingInset: CGFloat = 50
        static let columnSpacing: CGFloat = 12
        static let rowSpacing: CGFloat = 8
        static let rowHeight: CGFloat = 102
        static let innerTextHeight: CGFloat = 86
        static let iconSize: CGFloat = 40
        static let arrowSize: CGFloat = 32
        static let rawCornerRadius: CGFloat = 14
        static let innerCornerRadius: CGFloat = 10
        static let heroHeight: CGFloat = 154
    }

    private static let examples = [
        EnhancementExample(
            id: "message-format",
            raw: "Hey John, Newline, how are you doing today?",
            polished: "Hey John,\nHow are you doing today?"
        ),
        EnhancementExample(
            id: "correction",
            raw: "Hey, can we meet at five thirty tomorrow morning? Sorry, can you make it three thirty p.m. today?",
            polished: "Hey, can we meet at 3:30 PM today?"
        ),
        EnhancementExample(
            id: "list",
            raw: "Make a grocery list. First one is banana, second one is apple, third one is orange.",
            polished: "Grocery list:\n- banana\n- apple\n- orange"
        ),
    ]

    private var canNavigateOrMutate: Bool {
        !self.isRunning && !self.isRecordingShortcut
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                FluidOnboardingLandingBackdrop(glowCenter: self.glowCenter)

                VStack(spacing: 0) {
                    FluidOnboardingCompactProgress(value: self.progressValue)
                        .padding(.top, 28)

                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(spacing: 0) {
                            Color.clear
                                .frame(height: 22)

                            self.setupSection(containerWidth: proxy.size.width)
                        }
                        .frame(maxWidth: .infinity)
                    }

                    self.footer
                }
                .frame(width: proxy.size.width, height: proxy.size.height)

                FluidOnboardingLandingHoverTracker(
                    onMove: self.onGlowMove,
                    onExit: self.onGlowExit
                )
                .frame(width: proxy.size.width, height: proxy.size.height)
                .accessibilityHidden(true)
            }
        }
    }

    private func setupSection(containerWidth: CGFloat) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                FluidOnboardingCompactAppIconMark(size: 52)
                    .padding(.bottom, 18)

                Text("One more thing...")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 10)

                Text("Optional: connect your own AI provider to polish dictation.")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.64))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                    .frame(maxWidth: 700)
                    .padding(.horizontal, 32)
            }
            .frame(height: ExampleGridMetrics.heroHeight, alignment: .top)
            .padding(.bottom, 20)

            self.examplesPanel
                .frame(width: self.exampleGridWidth(containerWidth: containerWidth))
                .padding(.bottom, 18)

            Text("Want AI polishing?")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .padding(.bottom, 12)

            self.aiProviderCard
                .frame(width: min(containerWidth - 92, 840))
                .padding(.bottom, 12)

            Text("You can change this later in AI Enhancement settings.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.46))
        }
        .frame(maxWidth: .infinity)
    }

    private func exampleGridWidth(containerWidth: CGFloat) -> CGFloat {
        min(max(containerWidth - ExampleGridMetrics.widthInset, 360), ExampleGridMetrics.maxWidth)
    }

    private func exampleGridHeader(leftTitle: String, rightTitle: String) -> some View {
        HStack(spacing: ExampleGridMetrics.columnSpacing) {
            Text(leftTitle)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.48))
                .frame(maxWidth: .infinity, alignment: .center)

            Color.clear
                .frame(width: ExampleGridMetrics.arrowSize, height: 1)

            Text(rightTitle)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(FluidOnboardingLandingColors.blue.opacity(0.84))
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.leading, ExampleGridMetrics.headerLeadingInset)
    }

    private var examplesPanel: some View {
        VStack(spacing: ExampleGridMetrics.rowSpacing) {
            self.exampleGridHeader(leftTitle: "Raw dictation (before)", rightTitle: "Polished (after)")

            ForEach(Self.examples) { example in
                self.exampleRow(example)
            }
        }
    }

    private func exampleRow(_ example: EnhancementExample) -> some View {
        HStack(alignment: .center, spacing: ExampleGridMetrics.columnSpacing) {
            HStack(spacing: ExampleGridMetrics.columnSpacing) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(FluidOnboardingLandingColors.blue)
                    .frame(width: ExampleGridMetrics.iconSize, height: ExampleGridMetrics.iconSize)
                    .background(
                        Circle()
                            .fill(FluidOnboardingLandingColors.blue.opacity(0.12))
                            .overlay(
                                Circle()
                                    .stroke(FluidOnboardingLandingColors.blue.opacity(0.22), lineWidth: 1)
                            )
                    )

                Text(example.raw)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.52))
                    .lineLimit(4)
                    .minimumScaleFactor(0.80)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 10)
                    .frame(height: ExampleGridMetrics.innerTextHeight, alignment: .center)
                    .background(
                        RoundedRectangle(cornerRadius: ExampleGridMetrics.innerCornerRadius, style: .continuous)
                            .fill(Color.white.opacity(0.040))
                    )
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .frame(height: ExampleGridMetrics.rowHeight)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: ExampleGridMetrics.rawCornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.038))
                    .overlay(
                        RoundedRectangle(cornerRadius: ExampleGridMetrics.rawCornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(0.070), lineWidth: 1)
                    )
            )

            Image(systemName: "arrow.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white.opacity(0.80))
                .frame(width: ExampleGridMetrics.arrowSize, height: ExampleGridMetrics.arrowSize)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.065))
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.10), lineWidth: 1)
                        )
                )

            self.polishedExampleSurface(example)
        }
    }

    private func polishedExampleSurface(_ example: EnhancementExample) -> some View {
        let shape = RoundedRectangle(cornerRadius: ExampleGridMetrics.rawCornerRadius, style: .continuous)

        return ZStack(alignment: .topLeading) {
            Text(example.polished)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.84))
                .lineLimit(5)
                .minimumScaleFactor(0.80)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
        .frame(height: ExampleGridMetrics.rowHeight, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            shape
                .fill(FluidOnboardingLandingColors.blue.opacity(0.060))
                .overlay(
                    shape.stroke(FluidOnboardingLandingColors.blue.opacity(0.42), lineWidth: 1.2)
                )
        )
    }

    private var aiProviderCard: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        let isHovered = self.hoveredButtonID == "generic-ai-provider" && self.canNavigateOrMutate

        return HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("AI provider")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Label("Connect your own provider to polish dictation.", systemImage: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.74))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                HStack(spacing: 13) {
                    self.modelFact("key.fill", "Uses your API key")
                    self.modelFact("slider.horizontal.3", "Configurable later")
                    self.modelFact("network", "Cloud or local")
                }
            }

            Spacer(minLength: 12)

            self.pillButton(
                PillButtonConfiguration(
                    id: "generic-ai-provider",
                    title: "Set up provider",
                    systemImage: "arrow.up.right",
                    tone: .primary,
                    width: 168,
                    height: 40,
                    fontSize: 13,
                    isEnabled: self.canNavigateOrMutate
                ),
                action: self.onUseAIProvider
            )
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            shape
                .fill(Color.white.opacity(isHovered ? 0.070 : 0.052))
                .overlay(shape.stroke(FluidOnboardingLandingColors.blue.opacity(isHovered ? 0.42 : 0.26), lineWidth: 1))
                .shadow(color: FluidOnboardingLandingColors.blue.opacity(isHovered ? 0.18 : 0.08), radius: isHovered ? 18 : 10, x: 0, y: 5)
        )
        .onHover { isHovered in
            self.setHoveredButton(isHovered ? "generic-ai-provider" : nil)
        }
    }

    private func modelFact(_ systemImage: String, _ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(FluidOnboardingLandingColors.blue.opacity(0.86))

            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.58))
                .lineLimit(1)
                .minimumScaleFactor(0.76)
        }
    }

    private var footer: some View {
        HStack {
            self.pillButton(
                PillButtonConfiguration(
                    id: "back",
                    title: "Back",
                    systemImage: nil,
                    tone: .secondary,
                    width: 132,
                    height: 48,
                    fontSize: 16,
                    isEnabled: self.canNavigateOrMutate
                ),
                action: self.onBack
            )
            .keyboardShortcut(.cancelAction)

            Spacer()

            self.skipButton
        }
        .padding(.horizontal, 30)
        .padding(.bottom, 24)
    }

    private var skipButton: some View {
        self.pillButton(
            PillButtonConfiguration(
                id: "ai-skip",
                title: "Skip for now",
                systemImage: nil,
                tone: .secondary,
                width: 132,
                height: 48,
                fontSize: 16,
                isEnabled: self.canNavigateOrMutate
            ),
            action: self.onSkip
        )
    }

    private func pillButton(
        _ configuration: PillButtonConfiguration,
        action: @escaping () -> Void
    ) -> some View {
        let isDisabled = !configuration.isEnabled
        let isHovered = self.hoveredButtonID == configuration.id && !isDisabled
        let shape = Capsule()
        let accentColor = FluidOnboardingLandingColors.blue
        let isPrimary = configuration.tone == .primary
        let fillColor: Color = isPrimary
            ? accentColor.opacity(isDisabled ? 0.34 : 1)
            : Color.white.opacity(isDisabled ? 0.045 : (isHovered ? 0.11 : 0.07))
        let borderColor: Color = isPrimary
            ? Color.white.opacity(isHovered ? 0.30 : 0)
            : (isHovered ? accentColor.opacity(0.30) : Color.white.opacity(0.07))
        let foregroundOpacity = isDisabled ? 0.42 : (isPrimary ? 1.0 : (isHovered ? 0.94 : 0.78))
        let shadowOpacity = isDisabled ? 0 : (isPrimary ? (isHovered ? 0.56 : 0.26) : (isHovered ? 0.12 : 0))

        return Button(action: action) {
            HStack(spacing: configuration.systemImage == nil ? 0 : 8) {
                if let systemImage = configuration.systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .bold))
                }

                Text(configuration.title)
                    .font(.system(size: configuration.fontSize, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .foregroundStyle(.white.opacity(foregroundOpacity))
            .frame(width: configuration.width, height: configuration.height)
            .background(
                shape
                    .fill(fillColor)
                    .overlay(shape.fill(Color.white.opacity(isPrimary && isHovered ? 0.10 : 0)))
                    .overlay(shape.stroke(borderColor, lineWidth: isHovered ? 1.2 : 1))
                    .overlay(
                        shape
                            .stroke(accentColor.opacity(isHovered ? 0.50 : 0), lineWidth: isHovered ? 1.4 : 1)
                            .padding(-2)
                    )
                    .shadow(color: accentColor.opacity(shadowOpacity), radius: isHovered ? 16 : 9, x: 0, y: isHovered ? 6 : 3)
            )
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .contentShape(shape)
        .disabled(isDisabled)
        .onHover { isHovered in
            self.setHoveredButton(isHovered && !isDisabled ? configuration.id : nil)
        }
    }

    private func setHoveredButton(_ buttonID: String?) {
        guard self.hoveredButtonID != buttonID else { return }
        if self.reduceMotion {
            self.hoveredButtonID = buttonID
        } else {
            withAnimation(.easeOut(duration: 0.14)) {
                self.hoveredButtonID = buttonID
            }
        }
    }
}
