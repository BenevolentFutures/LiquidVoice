import Foundation

struct AnalyticsConfig {
    let postHogApiKey: String
    let postHogHost: String

    /// Default EU ingestion host.
    nonisolated static let defaultEUHost = "https://eu.i.posthog.com"

    nonisolated static func fromBundle() -> AnalyticsConfig {
        let info = Bundle.main.infoDictionary ?? [:]
        let key = (info["POSTHOG_API_KEY"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let host = (info["POSTHOG_HOST"] as? String ?? AnalyticsConfig.defaultEUHost).trimmingCharacters(in: .whitespacesAndNewlines)
        return AnalyticsConfig(postHogApiKey: key, postHogHost: host.isEmpty ? AnalyticsConfig.defaultEUHost : host)
    }

    /// MouthKeys ships with analytics permanently disabled.
    ///
    /// Upstream FluidVoice sends aggregate usage events to PostHog and enables this by
    /// default (see `SettingsStore.analyticsConsentEnabled`, which returns `true` when the
    /// user has never chosen). This fork does not phone home at all, so every send path —
    /// `bootstrap`, `write`, `startFlushLoopIfNeeded`, `flushIfNeeded` — short-circuits here.
    ///
    /// This is hard-wired rather than done by blanking `POSTHOG_API_KEY` in `Info.plist`
    /// alone, so that merging an upstream change to that plist cannot silently re-enable
    /// telemetry. The plist values are blanked too; both are required to turn it back on.
    nonisolated var isConfigured: Bool {
        false
    }
}
