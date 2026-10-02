//
//  FeedbackView.swift
//  fluid
//
//  Extracted from ContentView.swift to reduce monolithic architecture.
//  Created: 2025-12-14
//

import AppKit
import SwiftUI

struct FeedbackView: View {
    @Environment(\.theme) private var theme

    @State private var feedbackText: String = ""
    @State private var includeSystemInfo: Bool = true
    @State private var appear: Bool = false

    private var trimmedFeedback: String {
        self.feedbackText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "envelope.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(self.theme.palette.accent)
                        VStack(alignment: .leading) {
                            Text("Send Feedback")
                                .font(.system(size: 28, weight: .bold))
                            Text("Report a bug or suggest a change on the MouthKeys GitHub")
                                .font(.system(size: 16))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.bottom, 8)

                // Upstream credit
                ThemedCard(style: .prominent, hoverEffect: false) {
                    HStack(spacing: 12) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.pink)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("MouthKeys is built on FluidVoice by altic-dev")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(self.theme.palette.primaryText)

                            Text("FluidVoice is the open-source dictation app this fork comes from. If MouthKeys is useful to you, consider supporting its original author.")
                                .font(.system(size: 13))
                                .foregroundStyle(self.theme.palette.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()

                        HStack(spacing: 10) {
                            Link(destination: LiquidVoiceLinks.upstreamRepository) {
                                HStack(spacing: 8) {
                                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                                    Text("FluidVoice")
                                        .fontWeight(.semibold)
                                }
                                .font(.system(size: 14))
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                            }
                            .fluidButton(.glass, size: .medium)
                            .buttonHoverEffect()
                            .help("FluidVoice on GitHub")

                            Link(destination: LiquidVoiceLinks.upstreamSponsor) {
                                HStack(spacing: 8) {
                                    Image(systemName: "heart.fill")
                                    Text("Sponsor FluidVoice")
                                        .fontWeight(.semibold)
                                }
                                .font(.system(size: 14))
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                            }
                            .fluidButton(.glass, size: .medium)
                            .buttonHoverEffect()
                            .help("Sponsor altic-dev, FluidVoice's author, on GitHub")
                        }
                    }
                    .padding(20)
                }

                // Feedback Form
                ThemedCard(style: .standard, hoverEffect: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Feedback")
                                .font(.headline)
                                .fontWeight(.semibold)

                            TextEditor(text: self.$feedbackText)
                                .font(.system(size: 14))
                                .frame(height: 120)
                                .padding(12)
                                .background(RoundedRectangle(cornerRadius: 8)
                                    .fill(self.theme.palette.contentBackground)
                                    .overlay(RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(self.theme.palette.cardBorder.opacity(0.45), lineWidth: 1.2)))
                                .scrollContentBackground(.hidden)
                                .overlay(
                                    Group {
                                        if self.feedbackText.isEmpty {
                                            Text("Share your thoughts, report bugs, or suggest features...")
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                                .padding(.leading, 4)
                                        }
                                    }
                                    .allowsHitTesting(false)
                                )

                            Toggle("Include app and macOS version", isOn: self.$includeSystemInfo)
                                .toggleStyle(GlassToggleStyle())

                            HStack {
                                Text("Opens a prefilled issue in your browser. Nothing is sent until you submit it on GitHub.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Spacer()

                                Button(action: self.openFeedbackIssue) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "arrow.up.right.square")
                                        Text("Open GitHub Issue")
                                            .fontWeight(.semibold)
                                    }
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 10)
                                }
                                .fluidButton(.glass, size: .medium)
                                .disabled(self.trimmedFeedback.isEmpty)
                                .buttonHoverEffect()
                            }
                        }
                    }
                    .padding(20)
                }
                .modifier(CardAppearAnimation(delay: 0.1, appear: self.$appear))
            }
            .padding(24)
        }
        .onAppear {
            self.appear = true
        }
    }

    // MARK: - Feedback

    private func openFeedbackIssue() {
        let feedback = self.trimmedFeedback
        guard !feedback.isEmpty else { return }

        let url = LiquidVoiceLinks.prefilledIssueURL(
            title: LiquidVoiceLinks.issueTitle(forFeedback: feedback),
            body: feedback,
            footer: self.includeSystemInfo ? "---\n" + Self.systemInfo() : ""
        )
        DebugLogger.shared.info("Opening prefilled feedback issue on GitHub", source: "FeedbackView")
        NSWorkspace.shared.open(url)
    }

    private static func systemInfo() -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = info?["CFBundleVersion"] as? String ?? "unknown"
        return """
        MouthKeys \(version) (\(build))
        macOS \(ProcessInfo.processInfo.operatingSystemVersionString)
        """
    }
}

#Preview {
    FeedbackView()
}
