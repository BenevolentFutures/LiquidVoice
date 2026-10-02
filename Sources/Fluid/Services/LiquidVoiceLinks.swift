import Foundation

/// Every outbound link the app opens. MouthKeys' own links point at its fork; the only
/// upstream links are deliberate credit to FluidVoice by altic-dev, which MouthKeys is built on.
/// Nothing here is fetched: these URLs are only ever opened in the user's browser.
enum LiquidVoiceLinks {
    static let newIssue = URL(string: "https://github.com/BenevolentFutures/MouthKeys/issues/new")!
    /// The newest signed release. MouthKeys does not update itself; people download each release.
    static let latestRelease = URL(string: "https://github.com/BenevolentFutures/MouthKeys/releases/latest")!

    /// Upstream credit: the project MouthKeys is forked from, and its maintainer's sponsor page.
    static let upstreamRepository = URL(string: "https://github.com/altic-dev/FluidVoice")!
    static let upstreamSponsor = URL(string: "https://github.com/sponsors/altic-dev")!

    /// GitHub rejects very long URLs; keep the prefilled issue comfortably under its limit.
    static let maxIssueURLLength = 7500

    /// A new-issue URL on MouthKeys' GitHub with the title and body prefilled. Opening it
    /// sends nothing: the user reviews the draft and submits it on GitHub themselves. When the
    /// URL would be too long, `body` is shortened; `footer` (such as version info) is always kept.
    static func prefilledIssueURL(title: String, body: String, footer: String = "") -> URL {
        var keptCharacters = body.count
        while true {
            var draftBody = keptCharacters == body.count
                ? body
                : String(body.prefix(keptCharacters)) + "\n\n[truncated]"
            if !footer.isEmpty {
                draftBody += "\n\n" + footer
            }
            var components = URLComponents(url: self.newIssue, resolvingAgainstBaseURL: false)!
            components.percentEncodedQueryItems = [
                URLQueryItem(name: "title", value: self.encodeQueryValue(title)),
                URLQueryItem(name: "body", value: self.encodeQueryValue(draftBody)),
            ]
            let url = components.url!
            if url.absoluteString.count <= self.maxIssueURLLength || keptCharacters == 0 {
                return url
            }
            keptCharacters = max(0, keptCharacters - max(200, keptCharacters / 10))
        }
    }

    /// Issue title: the first line of the feedback, shortened.
    static func issueTitle(forFeedback feedback: String) -> String {
        let firstLine = feedback
            .split(whereSeparator: \.isNewline)
            .first
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
        guard !firstLine.isEmpty else { return "Feedback" }
        guard firstLine.count > 80 else { return firstLine }
        return String(firstLine.prefix(77)) + "..."
    }

    private static func encodeQueryValue(_ value: String) -> String {
        // Encode everything that could end a query value or be read as a space ("+").
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+?#")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }
}
