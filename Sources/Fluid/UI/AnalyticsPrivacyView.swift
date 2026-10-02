import SwiftUI

struct AnalyticsPrivacyView: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Analytics")
                        .font(.system(size: 18, weight: .semibold))
                    Text("MouthKeys sends no analytics or telemetry")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Done") { self.dismiss() }
                    .buttonStyle(.bordered)
            }

            Divider().opacity(0.4)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    self.sectionTitle("What MouthKeys sends")
                    self.bullet("No usage analytics, crash reports, or telemetry. The analytics backend upstream FluidVoice uses is switched off in this build, so there is nothing to opt in to or out of.")
                    self.bullet("Your transcripts and audio stay on this Mac unless you set up a cloud AI provider yourself. Then the text you choose to enhance goes to that provider.")

                    self.sectionTitle("Network use you may see")
                    self.bullet("Speech-model downloads, when you pick a model that is not on this Mac yet.")
                    self.bullet("Requests to AI providers you configure in AI Enhancement.")
                    self.bullet("Links you open yourself, such as Feedback, which opens GitHub in your browser.")
                }
                .padding(.vertical, 6)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(self.theme.palette.contentBackground)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(self.theme.palette.accent)
            .padding(.top, 4)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
    }
}
