import Foundation

/// A one-time offer to stop removing a filler word that a region actually says on purpose
/// ("eh" in Canada and Minnesota).
///
/// Detection is passive and local: the system region, the system time zone, and the words in
/// a dictation the user just made. No network lookup, so nothing about the user leaves the machine.
struct RegionalFillerOffer: Equatable {
    enum Region: String, CaseIterable {
        case canada
        case minnesota
    }

    let region: Region
    /// The filler word the offer keeps.
    let word: String
    let emoji: String
    let message: String
    let keepTitle: String

    // MARK: - Detection

    /// IANA zones (and their legacy `Canada/*` aliases) that only exist in Canada.
    /// US zones that share an offset use different identifiers (`America/New_York`, ...).
    static let canadianTimeZoneIdentifiers: Set<String> = [
        "America/St_Johns",
        "America/Halifax",
        "America/Glace_Bay",
        "America/Moncton",
        "America/Goose_Bay",
        "America/Blanc-Sablon",
        "America/Toronto",
        "America/Montreal",
        "America/Nipigon",
        "America/Thunder_Bay",
        "America/Iqaluit",
        "America/Pangnirtung",
        "America/Atikokan",
        "America/Winnipeg",
        "America/Rainy_River",
        "America/Resolute",
        "America/Rankin_Inlet",
        "America/Regina",
        "America/Swift_Current",
        "America/Edmonton",
        "America/Cambridge_Bay",
        "America/Yellowknife",
        "America/Inuvik",
        "America/Creston",
        "America/Dawson_Creek",
        "America/Fort_Nelson",
        "America/Vancouver",
        "America/Whitehorse",
        "America/Dawson",
        "Canada/Newfoundland",
        "Canada/Atlantic",
        "Canada/Eastern",
        "Canada/Central",
        "Canada/Saskatchewan",
        "Canada/Mountain",
        "Canada/Pacific",
        "Canada/Yukon",
    ]

    /// Minnesota has no zone of its own: a Mac there reports `America/Chicago`, like the rest of
    /// US Central time. These are the US Central zones, so the Minnesota offer asks, never claims,
    /// unless the dictation itself sounds Minnesotan.
    static let usCentralTimeZoneIdentifiers: Set<String> = [
        "America/Chicago",
        "America/Menominee",
        "America/North_Dakota/Center",
        "America/North_Dakota/New_Salem",
        "America/North_Dakota/Beulah",
        "US/Central",
    ]

    /// Phrases that give a Minnesotan away. ASR tends to spell "ope" as "oop".
    private static let minnesotanPhrase = try! NSRegularExpression(
        pattern: #"\b(ope|oop|uff ?da|you betcha|ya betcha|dontcha know|oh f[eo]r cute)\b"#,
        options: [.caseInsensitive]
    )

    static func isLikelyCanadian(locale: Locale = .current, timeZone: TimeZone = .current) -> Bool {
        if locale.region?.identifier == "CA" { return true }
        return self.canadianTimeZoneIdentifiers.contains(timeZone.identifier)
    }

    static func isUSCentral(timeZone: TimeZone = .current) -> Bool {
        self.usCentralTimeZoneIdentifiers.contains(timeZone.identifier)
    }

    static func soundsMinnesotan(_ text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        return self.minnesotanPhrase.firstMatch(in: text, range: range) != nil
    }

    // MARK: - Offer

    /// The offer to show, if any. It shows once, while its word is still being removed and the
    /// user has not answered. Canada wins over Minnesota.
    static func offer(
        fillerWords: [String],
        answered: Bool,
        removalEnabled: Bool = true,
        dictation: String? = nil,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> RegionalFillerOffer? {
        guard !answered, removalEnabled else { return nil }

        let candidate: RegionalFillerOffer?
        if self.isLikelyCanadian(locale: locale, timeZone: timeZone) {
            candidate = RegionalFillerOffer(
                region: .canada,
                word: "eh",
                emoji: "🍁",
                message: "Looks like you're in Canada. Keep \"eh\" in your transcripts, eh?",
                keepTitle: "Keep \"eh\""
            )
        } else if self.isUSCentral(timeZone: timeZone) {
            let sure = dictation.map(self.soundsMinnesotan) ?? false
            candidate = RegionalFillerOffer(
                region: .minnesota,
                word: "eh",
                emoji: "🌲",
                message: sure
                    ? "Ope, sounds like Minnesota. Keep \"eh\" in your transcripts?"
                    : "Minnesota, by any chance? Keep \"eh\" in your transcripts, ya?",
                keepTitle: "You betcha"
            )
        } else {
            candidate = nil
        }

        guard let candidate,
              fillerWords.contains(where: { $0.lowercased() == candidate.word })
        else { return nil }
        return candidate
    }

    static func offer(dictation: String? = nil, settings: SettingsStore = .shared) -> RegionalFillerOffer? {
        self.offer(
            fillerWords: settings.fillerWords,
            answered: settings.regionalFillerOfferAnswered,
            removalEnabled: settings.removeFillerWordsEnabled,
            dictation: dictation
        )
    }

    /// Records the answer. Keeping takes the word off the filler list; either answer ends every
    /// regional offer for good.
    @discardableResult
    func answer(keep: Bool, surface: String, settings: SettingsStore = .shared) -> [String] {
        var fillerWords = settings.fillerWords
        if keep {
            fillerWords.removeAll { $0.lowercased() == self.word }
            settings.fillerWords = fillerWords
        }
        settings.regionalFillerOfferAnswered = true
        DebugLogger.shared.info(
            "REGIONAL_FILLER_OFFER answered region=\(self.region.rawValue) word=\(self.word) keep=\(keep) surface=\(surface)",
            source: "RegionalFillerOffer"
        )
        return fillerWords
    }
}
