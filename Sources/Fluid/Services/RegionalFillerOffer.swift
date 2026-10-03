import Foundation

/// A one-time offer to stop removing a filler word that a region actually says on purpose
/// ("eh" in Canada, New Zealand, Queensland, Michigan and Minnesota; "ah" in Singapore and Malaysia).
///
/// Detection is passive and local: the system region, the system time zone, and the words in
/// a dictation the user just made. No network lookup, so nothing about the user leaves the machine.
struct RegionalFillerOffer: Equatable {
    enum Region: String, CaseIterable {
        case canada
        case newZealand
        case singapore
        case malaysia
        case queensland
        case michigan
        case minnesota
    }

    let region: Region
    /// The filler word the offer keeps.
    let word: String
    let emoji: String
    let message: String
    let keepTitle: String

    // MARK: - Regions

    /// One region's offer. A Mac matches when its system region is in `regionCodes` or its time
    /// zone is in `timeZones`. Zones listed here exist only in that place, so a match is a
    /// statement; Minnesota is the exception (see `usCentralTimeZoneIdentifiers`).
    struct Rule: Sendable {
        let region: Region
        let word: String
        let emoji: String
        let regionCodes: Set<String>
        let timeZones: Set<String>
        let keepTitle: String
        let message: @Sendable (_ dictation: String?) -> String

        func matches(locale: Locale, timeZone: TimeZone) -> Bool {
            if let code = locale.region?.identifier, self.regionCodes.contains(code) { return true }
            return self.timeZones.contains(timeZone.identifier)
        }
    }

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
    /// US Central time. So the Minnesota offer asks, never claims, unless the dictation itself
    /// sounds Minnesotan.
    static let usCentralTimeZoneIdentifiers: Set<String> = [
        "America/Chicago",
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

    static func soundsMinnesotan(_ text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        return self.minnesotanPhrase.firstMatch(in: text, range: range) != nil
    }

    /// First match wins, so countries matched by region come before the US states matched by zone.
    static let rules: [Rule] = [
        Rule(
            region: .canada,
            word: "eh",
            emoji: "🍁",
            regionCodes: ["CA"],
            timeZones: RegionalFillerOffer.canadianTimeZoneIdentifiers,
            keepTitle: "Keep \"eh\"",
            message: { _ in "Looks like you're in Canada. Keep \"eh\" in your transcripts, eh?" }
        ),
        Rule(
            region: .newZealand,
            word: "eh",
            emoji: "🥝",
            regionCodes: ["NZ"],
            timeZones: ["Pacific/Auckland", "Pacific/Chatham", "NZ", "NZ-CHAT"],
            keepTitle: "Sweet as",
            message: { _ in "Kia ora! Keep \"eh\" in your transcripts? Sweet as, eh." }
        ),
        Rule(
            region: .singapore,
            word: "ah",
            emoji: "🦁",
            regionCodes: ["SG"],
            timeZones: ["Asia/Singapore", "Singapore"],
            keepTitle: "Can lah",
            message: { _ in "Singapore ah? Keep \"ah\" in your transcripts or not?" }
        ),
        Rule(
            region: .malaysia,
            word: "ah",
            emoji: "🌺",
            regionCodes: ["MY"],
            timeZones: ["Asia/Kuala_Lumpur", "Asia/Kuching"],
            keepTitle: "Boleh lah",
            message: { _ in "Malaysia ah? Keep \"ah\" in your transcripts or not?" }
        ),
        Rule(
            region: .queensland,
            word: "eh",
            emoji: "☀️",
            regionCodes: [],
            timeZones: ["Australia/Brisbane", "Australia/Lindeman", "Australia/Queensland"],
            keepTitle: "Too right",
            message: { _ in "G'day, Queensland. Keep \"eh\" in your transcripts, eh?" }
        ),
        Rule(
            region: .michigan,
            word: "eh",
            emoji: "🧤",
            regionCodes: [],
            timeZones: ["America/Detroit", "America/Menominee", "US/Michigan"],
            keepTitle: "Oh yah",
            message: { _ in "Michigan, eh? Keep \"eh\" in your transcripts?" }
        ),
        Rule(
            region: .minnesota,
            word: "eh",
            emoji: "🌲",
            regionCodes: [],
            timeZones: RegionalFillerOffer.usCentralTimeZoneIdentifiers,
            keepTitle: "You betcha",
            message: { dictation in
                dictation.map(RegionalFillerOffer.soundsMinnesotan) == true
                    ? "Ope, sounds like Minnesota. Keep \"eh\" in your transcripts?"
                    : "Minnesota, by any chance? Keep \"eh\" in your transcripts, ya?"
            }
        ),
    ]

    // MARK: - Offer

    /// The offer to show, if any. It shows once, while its word is still being removed and the
    /// user has not answered.
    static func offer(
        fillerWords: [String],
        answered: Bool,
        removalEnabled: Bool = true,
        dictation: String? = nil,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> RegionalFillerOffer? {
        guard !answered, removalEnabled,
              let rule = self.rules.first(where: { $0.matches(locale: locale, timeZone: timeZone) }),
              fillerWords.contains(where: { $0.lowercased() == rule.word })
        else { return nil }

        return RegionalFillerOffer(
            region: rule.region,
            word: rule.word,
            emoji: rule.emoji,
            message: rule.message(dictation),
            keepTitle: rule.keepTitle
        )
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
