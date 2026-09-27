import Foundation

/// Every outbound link the app opens. Liquid Voice's own links point at its fork; the only
/// upstream links are deliberate credit to FluidVoice by altic-dev, which Liquid Voice is built on.
/// Nothing here is fetched: these URLs are only ever opened in the user's browser.
enum LiquidVoiceLinks {
    static let repository = URL(string: "https://github.com/BenevolentFutures/LiquidVoice")!
    static let newIssue = URL(string: "https://github.com/BenevolentFutures/LiquidVoice/issues/new")!

    /// Upstream credit: the project Liquid Voice is forked from, and its maintainer's sponsor page.
    static let upstreamRepository = URL(string: "https://github.com/altic-dev/FluidVoice")!
    static let upstreamSponsor = URL(string: "https://github.com/sponsors/altic-dev")!

    /// GitHub rejects very long URLs; keep the prefilled issue comfortably under its limit.
    static let maxIssueURLLength = 7500

    /// A new-issue URL on Liquid Voice's GitHub with the title and body prefilled. Opening it
    /// sends nothing: the user reviews the draft and submits it on GitHub themselves.
    static func prefilledIssueURL(title: String, body: String) -> URL {
        var keptCharacters = body.count
        while true {
            let draftBody = keptCharacters == body.count
                ? body
                : String(body.prefix(keptCharacters)) + "\n\n[truncated]"
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
