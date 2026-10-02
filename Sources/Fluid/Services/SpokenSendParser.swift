import CoreGraphics
import Foundation

// Spoken Send phrase detection. Ported from altic-dev/FluidVoice by altic-dev:
//   @c679506d add spoken send commands (the parser, the "literal" escape, the countdown checks)
//   @95fe1b15 complete spoken send after quiet countdown (no fresh-partial requirement)
//   @60480451 hold the armed phrase across noisy partials (arming state, near-miss final parse)
// MouthKeys additions:
// - The phrase is part of the sentence, not a command, when a question mark follows it ("Can
//   you send it?") or when the word before it is a negation, subject pronoun, modal or "to"
//   ("but don't send it", "I'll send it", "can you send it", "want to send it"). This holds for
//   the final parse, for arming during streaming, and for the armed near miss ("I already sent
//   it"). Object pronouns do not count ("Thank you send it", "Do it for me send it" send).
// - A dangling lead-in before the phrase goes with it: "and", "and then", "let's", "just", "go
//   ahead and" ("Fix the typo and send it" types "Fix the typo."; "Yes, go ahead and send it"
//   types "Yes"). When nothing but filler comes before it ("Just send it", "Um, send it"),
//   nothing is typed and the draft is sent. Affirmations are answers and are typed ("Okay send
//   it" types "Okay").
// - "literal" escapes the phrase with a comma, colon or semicolon after it ("literal, send it"),
//   but not across a sentence ("Take it literal. Send it." sends).
// - For a terminal (c11) no sentence ending is added, and only one sentence-ending period right
//   after a letter or digit is dropped: "slash compact send it" types "/compact", "cd .. send
//   it" keeps "cd ..", "git add . send it" keeps "git add .".

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
            if precedingWord.map({ $0.text.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ",:;")) }) == "literal" { continue }
            guard let firstTailWord = tail.first else { continue }
            // "I already sent it" reports; it does not command.
            if self.phraseIsPartOfSentence(before: text[..<firstTailWord.range.lowerBound]) { continue }

            let normalizedTail = tail.map { self.normalizeWord($0.text) }.joined()
            guard normalizedTail.first == normalizedPhrase.first,
                  self.editDistance(normalizedTail, normalizedPhrase) <= tolerance
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
    /// The phrase anywhere else ("I'll send it tomorrow"), ending a question ("Can you send
    /// it?"), or after a negation, pronoun, modal or "to" ("but don't send it", "I'll send
    /// it") is ordinary text. "literal send it" types the phrase without sending.
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
            pattern: #"(?i)(?<![\p{L}\p{N}_])literal[\s,:;]+("# + phrasePattern + #")"# + trailingPunctuation
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
        ) else {
            return SpokenSendParseResult(text: text, shouldSend: false)
        }
        // The run of phrases that ends the text. When the sentence owns its first phrase ("I'll
        // send it, send it"), the command is the repeat after it, if there is one.
        var searchStart = text.startIndex
        var found: (command: Range<String.Index>, firstPhrase: Range<String.Index>)?
        while found == nil {
            guard let match = commandRegex.firstMatch(in: text, range: NSRange(searchStart..., in: text)),
                  match.range.location != NSNotFound,
                  let commandRange = Range(match.range, in: text),
                  let firstPhraseRange = Range(match.range(at: 1), in: text)
            else {
                return SpokenSendParseResult(text: text, shouldSend: false)
            }
            if self.phraseIsPartOfSentence(before: text[..<firstPhraseRange.lowerBound]) {
                searchStart = firstPhraseRange.upperBound
            } else {
                found = (commandRange, firstPhraseRange)
            }
        }
        guard let (commandRange, firstPhraseRange) = found else {
            return SpokenSendParseResult(text: text, shouldSend: false)
        }

        var commandPrefix = String(text[..<commandRange.lowerBound])
        if let literalPrefixRegex = try? NSRegularExpression(
            pattern: #"(?i)(?<![\p{L}\p{N}_])literal[\s,:;]*$"#
        ), let literalMatch = literalPrefixRegex.firstMatch(
            in: commandPrefix,
            range: NSRange(commandPrefix.startIndex..., in: commandPrefix)
        ), let literalRange = Range(literalMatch.range, in: commandPrefix) {
            commandPrefix.replaceSubrange(literalRange, with: text[firstPhraseRange])
        }

        let cleaned = Self.polishCommandPrefix(commandPrefix, forTerminal: forTerminal)
        return SpokenSendParseResult(text: cleaned, shouldSend: true)
    }

    /// Words that make the phrase right after them part of the sentence: "but don't send it",
    /// "I'll send it", "can you send it", "want to send it". Lowercased, straight apostrophes.
    /// "me" and "us" are absent (they cannot be the subject: "Do it for me send it" sends), and
    /// so is "let's" ("OK let's send it" sends).
    private static let sentenceWords: Set<String> = [
        // negations (any word ending in "n't" counts too)
        "not", "never", "cannot", "dont", "doesnt", "didnt", "wont", "cant", "shouldnt", "wouldnt",
        "couldnt", "isnt", "arent", "wasnt", "werent", "havent", "hasnt", "mustnt",
        // subject pronouns (see `objectMarkers`) and their contractions
        "i", "you", "we", "they", "he", "she",
        "i'll", "you'll", "we'll", "they'll", "he'll", "she'll", "i'd", "you'd", "we'd", "they'd",
        // modals, auxiliaries, "to"
        "will", "would", "can", "could", "should", "shall", "may", "might", "must",
        "do", "does", "did", "gonna", "wanna", "gotta", "to",
    ]

    /// A pronoun right after one of these is an object, not the subject of the phrase: "Thank
    /// you send it", "Up to you send it" send. Transcribers often drop the comma there.
    /// Not "like" or "than": a subject can follow them ("It's not like I send it", "Faster than
    /// we send it").
    private static let objectMarkers: Set<String> = [
        "thank", "thanks", "to", "for", "with", "at", "from", "about", "by", "of", "without",
    ]

    private static let subjectPronouns: Set<String> = ["i", "you", "we", "they", "he", "she"]

    /// Adverbs looked past on the way back: "I'll just send it", "I already sent it".
    private static let passedOverWords: Set<String> = [
        "just", "already", "also", "really", "actually", "probably", "definitely", "still",
        "ever", "even", "only", "then", "now", "please",
    ]

    /// Whether the phrase that starts where `prefix` ends belongs to the sentence before it. Only
    /// words joined to the phrase by whitespace count: punctuation ("Fix it, send it") is a
    /// break, and a break means the phrase is a command.
    private static func phraseIsPartOfSentence(before prefix: Substring) -> Bool {
        var end = prefix.endIndex
        for _ in 0..<3 {
            guard let (word, start) = self.joinedWord(endingAt: end, in: prefix) else { return false }
            if self.subjectPronouns.contains(word) {
                // "Thank you send it", "Up to you send it": an object, so a break.
                if let (before, _) = self.joinedWord(endingAt: start, in: prefix), self.objectMarkers.contains(before) {
                    return false
                }
                return true
            }
            if self.sentenceWords.contains(word) || word.hasSuffix("n't") { return true }
            guard self.passedOverWords.contains(word) else { return false }
            end = start
        }
        return false
    }

    /// The word that ends at `end`, joined to what follows by whitespace only, lowercased with
    /// straight apostrophes, and where it starts. Nil at the start of the text or when
    /// punctuation comes first.
    private static func joinedWord(endingAt end: String.Index, in text: Substring) -> (word: String, start: String.Index)? {
        func isWordCharacter(_ character: Character) -> Bool {
            character.isLetter || character.isNumber || character == "'" || character == "’"
        }
        var index = end
        while index > text.startIndex, text[text.index(before: index)].isWhitespace {
            index = text.index(before: index)
        }
        let wordEnd = index
        while index > text.startIndex, isWordCharacter(text[text.index(before: index)]) {
            index = text.index(before: index)
        }
        guard index < wordEnd else { return nil }
        return (text[index..<wordEnd].lowercased().replacingOccurrences(of: "’", with: "'"), index)
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
        let trim: (String) -> String = { forTerminal ? self.trimTerminalTail($0) : self.trimTrailingSeparators($0) }
        var polished = trim(text)
        // A lead-in that joined the text to the command goes with it: "Fix the typo and send it",
        // "…, and then send it", "…, let's send it", "…, just send it", "Yes, go ahead and send
        // it". None of these can end a real sentence; "then" or "so" alone can ("See you then"),
        // and so can "go ahead" without its "and", so they stay.
        var strippedAnd = false
        for _ in 0..<4 {
            let prefixWords = self.lastWords(polished, count: 2)
            guard let last = prefixWords.last, last.text.allSatisfy({ $0.isLetter || $0 == "'" || $0 == "’" }) else { break }
            let lastWord = self.normalizeWord(last.text)
            let wordBefore = prefixWords.count >= 2 ? prefixWords[prefixWords.count - 2] : nil
            let cutAt: String.Index
            if lastWord == "and" || lastWord == "lets" || lastWord == "just" {
                strippedAnd = strippedAnd || lastWord == "and"
                cutAt = last.range.lowerBound
            } else if let wordBefore, wordBefore.text.allSatisfy(\.isLetter),
                      (lastWord == "then" && self.normalizeWord(wordBefore.text) == "and")
                      || (strippedAnd && lastWord == "ahead" && self.normalizeWord(wordBefore.text) == "go")
            {
                cutAt = wordBefore.range.lowerBound
            } else {
                break
            }
            polished = trim(String(polished[..<cutAt]))
        }

        // "Just send it", "Um, please send it": nothing but filler. Send the draft that is
        // already there and type nothing. ("Okay send it" types "Okay": it answers.)
        if self.isOnlyLeadIn(polished) {
            return ""
        }

        if forTerminal {
            // One sentence-ending period, right after a letter or digit: "Git status." submits
            // "Git status". Never "cd ..", "git add .", or "v1.2" beyond its last period.
            let lastTwo = Array(polished.suffix(2))
            if lastTwo.count == 2, lastTwo[1] == ".", lastTwo[0].isLetter || lastTwo[0].isNumber {
                polished.removeLast()
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

    /// Pure filler: when nothing else comes before the phrase, nothing is typed. Affirmations
    /// ("yes", "okay", "sure", "go ahead") are not here: they answer Claude, so they are typed.
    private static let leadInWords: Set<String> = [
        "just", "please", "now", "so", "then", "and", "well", "um", "uh", "oh", "lets",
    ]

    /// Stops at the first word that is not a lead-in, so a long dictation costs one word.
    private static func isOnlyLeadIn(_ text: String) -> Bool {
        var sawWord = false
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
            let token = text[start..<index]
            guard token.contains(where: { $0.isLetter || $0.isNumber }) else { continue }
            guard self.leadInWords.contains(self.normalizeWord(token)) else { return false }
            sawWord = true
        }
        return sawWord
    }

    /// The last `count` words of `text`, scanned from the end (the prefix can be a long dictation).
    private static func lastWords(_ text: String, count: Int) -> [Word] {
        var found: [Word] = []
        var index = text.endIndex
        while index > text.startIndex, found.count < count {
            let before = text.index(before: index)
            guard !text[before].isWhitespace else {
                index = before
                continue
            }
            let end = index
            while index > text.startIndex, !text[text.index(before: index)].isWhitespace {
                index = text.index(before: index)
            }
            let word = text[index..<end]
            if word.contains(where: { $0.isLetter || $0.isNumber }) {
                found.insert(Word(text: word, range: index..<end), at: 0)
            }
        }
        return found
    }

    /// The terminal version of `trimTrailingSeparators`: the transcriber's dashes go, and so does
    /// a comma, semicolon, colon or hyphen stuck to the word before it ("README," "Ready:"), but
    /// one standing alone after a space is an argument and stays ("cd -", "git log :").
    private static func trimTerminalTail(_ text: String) -> String {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = trimmed.last {
            let before = trimmed.dropLast().last
            let stuckToWord = before.map { $0.isLetter || $0.isNumber } ?? false
            guard last == "—" || last == "–" || (stuckToWord && [",", ";", ":", "-"].contains(last)) else { break }
            trimmed.removeLast()
            trimmed = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
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
