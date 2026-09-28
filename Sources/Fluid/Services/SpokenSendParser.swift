import CoreGraphics
import Foundation

// Spoken Send phrase detection. Ported from altic-dev/FluidVoice by altic-dev:
//   @c679506d add spoken send commands (the parser, the "literal" escape, the countdown checks)
//   @95fe1b15 complete spoken send after quiet countdown (no fresh-partial requirement)
//   @60480451 hold the armed phrase across noisy partials (arming state, near-miss final parse)
// Liquid Voice additions: a phrase followed by a question mark is part of a question, not a
// command ("Can you send it?"); a dangling "and" / "and then" before the phrase is dropped
// with it ("Fix the typo and send it" types "Fix the typo."); and for a terminal (c11) no
// sentence ending is added and a trailing period is dropped, since the text is a prompt or a
// command that is about to be submitted ("slash compact send it" types "/compact").

nonisolated struct SpokenSendParseResult: Equatable, Sendable {
    let text: String
    let shouldSend: Bool
}

/// Tracks whether streaming partials have armed the spoken send.
nonisolated struct SpokenSendArmingState: Equatable, Sendable {
    private(set) var armedText: String?

    var wasArmed: Bool { self.armedText != nil }

    mutating func reset() {
        self.armedText = nil
    }

    /// Returns whether this partial keeps the send armed. Only a live partial may
    /// disarm, so the final stop still knows the send was armed.
    mutating func update(partial: String, isEligible: Bool, phrase: String) -> Bool {
        guard isEligible else { return false }
        if SpokenSendParser.parse(partial, phrase: phrase, enabled: true).shouldSend {
            self.armedText = partial
            return true
        }
        if let armedText = self.armedText,
           SpokenSendParser.wordCount(partial) <= SpokenSendParser.wordCount(armedText)
        {
            return true
        }
        self.armedText = nil
        return false
    }
}

nonisolated enum SpokenSendParser {
    /// How long the quiet countdown runs after the phrase before dictation stops and sends.
    static let immediateStopSettleDuration: TimeInterval = 1.5
    /// The silence the end of the countdown needs, measured from the last voice activity.
    static let immediateStopRequiredSilenceDuration: TimeInterval = 0.35
    /// Voice activity this soon after the countdown starts is the tail of the phrase itself.
    static let immediateStopVoiceActivityGraceDuration: TimeInterval = 0.35
    /// The audio level that counts as speaking.
    static let immediateStopVoiceActivityLevelThreshold: CGFloat = 0.12

    static func shouldStopImmediately(
        _ text: String,
        phrase: String,
        spokenSendEnabled: Bool,
        sendImmediatelyEnabled: Bool,
        armedText: String? = nil
    ) -> Bool {
        sendImmediatelyEnabled &&
            self.isArmed(text, armedText: armedText, phrase: phrase, enabled: spokenSendEnabled)
    }

    static func canCompleteImmediateStop(
        _ text: String,
        phrase: String,
        spokenSendEnabled: Bool,
        sendImmediatelyEnabled: Bool,
        quietDuration: TimeInterval,
        armedText: String? = nil
    ) -> Bool {
        quietDuration >= self.immediateStopRequiredSilenceDuration &&
            self.shouldStopImmediately(
                text,
                phrase: phrase,
                spokenSendEnabled: spokenSendEnabled,
                sendImmediatelyEnabled: sendImmediatelyEnabled,
                armedText: armedText
            )
    }

    /// Streaming partials re-decode the same audio every few hundred milliseconds, so the trailing
    /// phrase can flip between "send it", "sent it" and "send" without the speaker saying anything new.
    /// Once armed, stay armed while a later partial has no more words than the armed transcript.
    static func isArmed(_ text: String, armedText: String?, phrase: String, enabled: Bool) -> Bool {
        guard enabled else { return false }
        if self.parse(text, phrase: phrase, enabled: true).shouldSend {
            return true
        }
        guard let armedText else { return false }
        return self.wordCount(text) <= self.wordCount(armedText)
    }

    /// Like `parse`, but when the send was already armed from streaming partials it also accepts
    /// a final transcript whose trailing words are a near miss of the phrase, such as "sent it".
    static func parseArmed(
        _ text: String,
        phrase: String,
        enabled: Bool,
        wasArmed: Bool,
        forTerminal: Bool = false
    ) -> SpokenSendParseResult {
        let strict = self.parse(text, phrase: phrase, enabled: enabled, forTerminal: forTerminal)
        guard enabled, wasArmed, !strict.shouldSend, strict.text == text, !self.endsAsQuestion(text) else { return strict }

        let phraseWords = self.words(phrase)
        let textWords = self.words(text)
        guard !phraseWords.isEmpty else { return strict }

        let normalizedPhrase = phraseWords.map { self.normalizeWord($0.text) }.joined()
        // Very short phrases have no room for a near miss ("end" must not pass as "send").
        let tolerance = normalizedPhrase.count >= 5 ? max(1, normalizedPhrase.count / 5) : 0
        guard tolerance > 0 else { return strict }

        // The phrase may come back merged ("sendit") or split, so try every tail length up to the phrase length.
        for tailLength in stride(from: min(phraseWords.count, textWords.count), through: 1, by: -1) {
            let tail = textWords.suffix(tailLength)
            let precedingWord = textWords.dropLast(tailLength).last
            if precedingWord.map({ self.normalizeWord($0.text) }) == "literal" { continue }

            let normalizedTail = tail.map { self.normalizeWord($0.text) }.joined()
            guard normalizedTail.first == normalizedPhrase.first,
                  self.editDistance(normalizedTail, normalizedPhrase) <= tolerance,
                  let firstTailWord = tail.first
            else { continue }

            let prefix = String(text[..<firstTailWord.range.lowerBound])
            return SpokenSendParseResult(text: self.polishCommandPrefix(prefix, forTerminal: forTerminal), shouldSend: true)
        }
        return strict
    }

    static func shouldCancelCountdownForVoiceActivity(
        countdownStartedAt: TimeInterval,
        voiceActivityAt: TimeInterval
    ) -> Bool {
        voiceActivityAt - countdownStartedAt >= self.immediateStopVoiceActivityGraceDuration
    }

    static func isMeaningfulVoiceActivity(_ level: CGFloat) -> Bool {
        level >= self.immediateStopVoiceActivityLevelThreshold
    }

    /// Detects the send phrase at the very end of `text` and strips it, with its punctuation.
    /// The phrase anywhere else ("I'll send it tomorrow"), or ending a question ("Can you send
    /// it?"), is ordinary text. "literal send it" types the phrase without sending.
    /// `forTerminal`: the text goes to a terminal, so no sentence ending is added.
    static func parse(_ text: String, phrase: String, enabled: Bool, forTerminal: Bool = false) -> SpokenSendParseResult {
        guard enabled else {
            return SpokenSendParseResult(text: text, shouldSend: false)
        }

        let phraseWords = phrase
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        guard !phraseWords.isEmpty else {
            return SpokenSendParseResult(text: text, shouldSend: false)
        }

        let phrasePattern = phraseWords
            .map(NSRegularExpression.escapedPattern(for:))
            .joined(separator: #"\s+"#)
        let trailingPunctuation = #"[\s\p{P}]*$"#

        if let literalRegex = try? NSRegularExpression(
            pattern: #"(?i)(?<![\p{L}\p{N}_])literal\s+("# + phrasePattern + #")"# + trailingPunctuation
        ), let match = literalRegex.firstMatch(
            in: text,
            range: NSRange(text.startIndex..., in: text)
        ), match.range.location != NSNotFound,
        let wholeRange = Range(match.range, in: text),
        let phraseRange = Range(match.range(at: 1), in: text) {
            var output = text
            output.replaceSubrange(wholeRange, with: text[phraseRange])
            return SpokenSendParseResult(text: output, shouldSend: false)
        }

        // "Can you send it?" asks something; it is not a command.
        guard !self.endsAsQuestion(text) else {
            return SpokenSendParseResult(text: text, shouldSend: false)
        }

        guard let commandRegex = try? NSRegularExpression(
            pattern: #"(?i)(?<![\p{L}\p{N}_])("# +
                phrasePattern +
                #")(?:[\s\p{P}]+"# +
                phrasePattern +
                #")*"# +
                trailingPunctuation
        ), let match = commandRegex.firstMatch(
            in: text,
            range: NSRange(text.startIndex..., in: text)
        ), match.range.location != NSNotFound,
        let commandRange = Range(match.range, in: text),
        let firstPhraseRange = Range(match.range(at: 1), in: text)
        else {
            return SpokenSendParseResult(text: text, shouldSend: false)
        }

        var commandPrefix = String(text[..<commandRange.lowerBound])
        if let literalPrefixRegex = try? NSRegularExpression(
            pattern: #"(?i)(?<![\p{L}\p{N}_])literal\s*$"#
        ), let literalMatch = literalPrefixRegex.firstMatch(
            in: commandPrefix,
            range: NSRange(commandPrefix.startIndex..., in: commandPrefix)
        ), let literalRange = Range(literalMatch.range, in: commandPrefix) {
            commandPrefix.replaceSubrange(literalRange, with: text[firstPhraseRange])
        }

        let cleaned = Self.polishCommandPrefix(commandPrefix, forTerminal: forTerminal)
        return SpokenSendParseResult(text: cleaned, shouldSend: true)
    }

    /// Whether the punctuation after the last word holds a question mark.
    private static func endsAsQuestion(_ text: String) -> Bool {
        let tail = text.reversed().prefix { $0.isWhitespace || $0.isPunctuation || $0.isSymbol }
        return tail.contains("?") || tail.contains("？")
    }

    private struct Word {
        let text: Substring
        let range: Range<String.Index>
    }

    private static func words(_ text: String) -> [Word] {
        var words: [Word] = []
        var index = text.startIndex
        while index < text.endIndex {
            guard !text[index].isWhitespace else {
                index = text.index(after: index)
                continue
            }
            let start = index
            while index < text.endIndex, !text[index].isWhitespace {
                index = text.index(after: index)
            }
            let word = text[start..<index]
            if word.contains(where: { $0.isLetter || $0.isNumber }) {
                words.append(Word(text: word, range: start..<index))
            }
        }
        return words
    }

    static func wordCount(_ text: String) -> Int {
        self.words(text).count
    }

    private static func normalizeWord<S: StringProtocol>(_ word: S) -> String {
        String(word.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    private static func editDistance(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs), b = Array(rhs)
        guard !a.isEmpty else { return b.count }
        guard !b.isEmpty else { return a.count }
        var previous = Array(0...b.count)
        for (i, ca) in a.enumerated() {
            var current = [i + 1]
            current.reserveCapacity(b.count + 1)
            for (j, cb) in b.enumerated() {
                let substitution = previous[j] + (ca == cb ? 0 : 1)
                current.append(min(previous[j + 1] + 1, current[j] + 1, substitution))
            }
            previous = current
        }
        return previous[b.count]
    }

    private static let trailingSeparators: Set<Character> = [",", ";", ":", "-", "–", "—"]

    /// Tidies the text before the phrase: no dangling separator or "and" / "and then", and a
    /// sentence ending where the phrase was. For a terminal, the ending is taken off instead: a
    /// command or a slash command must not be submitted with a period ("git status.").
    private static func polishCommandPrefix(_ text: String, forTerminal: Bool) -> String {
        var polished = self.trimTrailingSeparators(text)
        // "Fix the typo and send it": the "and" joined the text to the command. Only "and" (and
        // "and then") are dropped; "then" or "so" alone can end a real sentence ("See you then").
        let prefixWords = self.words(polished)
        if let last = prefixWords.last, self.normalizeWord(last.text) == "and", last.text.allSatisfy(\.isLetter) {
            polished = self.trimTrailingSeparators(String(polished[..<last.range.lowerBound]))
        } else if prefixWords.count >= 2,
                  self.normalizeWord(prefixWords[prefixWords.count - 2].text) == "and",
                  prefixWords[prefixWords.count - 2].text.allSatisfy(\.isLetter),
                  self.normalizeWord(prefixWords[prefixWords.count - 1].text) == "then",
                  prefixWords[prefixWords.count - 1].text.allSatisfy(\.isLetter)
        {
            polished = self.trimTrailingSeparators(String(polished[..<prefixWords[prefixWords.count - 2].range.lowerBound]))
        }

        if forTerminal {
            while polished.last == "." {
                polished.removeLast()
                polished = self.trimTrailingSeparators(polished)
            }
            return polished
        }
        guard let last = polished.last else {
            return polished
        }
        if [".", "?", "!", "…"].contains(last) {
            return polished
        }
        return polished + "."
    }

    private static func trimTrailingSeparators(_ text: String) -> String {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = trimmed.last, self.trailingSeparators.contains(last) {
            trimmed.removeLast()
            while trimmed.last?.isWhitespace == true {
                trimmed.removeLast()
            }
        }
        return trimmed
    }
}
