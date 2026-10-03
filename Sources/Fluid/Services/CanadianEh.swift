import Foundation

/// Decides whether to offer Canadian users to keep "eh" out of the filler-word list.
///
/// Detection is passive and local: the system region and the system time zone. No network
/// lookup, so nothing about the user leaves the machine.
enum CanadianEh {
    static let word = "eh"

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

    static func isLikelyCanadian(locale: Locale = .current, timeZone: TimeZone = .current) -> Bool {
        if locale.region?.identifier == "CA" { return true }
        return self.canadianTimeZoneIdentifiers.contains(timeZone.identifier)
    }

    /// The offer shows once: only while "eh" is still being removed and the user has not answered.
    static func shouldOffer(
        fillerWords: [String],
        answered: Bool,
        removalEnabled: Bool = true,
        isLikelyCanadian: Bool = CanadianEh.isLikelyCanadian()
    ) -> Bool {
        !answered && removalEnabled && isLikelyCanadian && fillerWords.contains { $0.lowercased() == self.word }
    }

    static func shouldOffer(settings: SettingsStore = .shared) -> Bool {
        self.shouldOffer(
            fillerWords: settings.fillerWords,
            answered: settings.canadianEhOfferAnswered,
            removalEnabled: settings.removeFillerWordsEnabled
        )
    }

    /// Records the answer. Keeping "eh" takes it off the filler list; either answer ends the offer.
    @discardableResult
    static func answer(keep: Bool, surface: String, settings: SettingsStore = .shared) -> [String] {
        var fillerWords = settings.fillerWords
        if keep {
            fillerWords.removeAll { $0.lowercased() == self.word }
            settings.fillerWords = fillerWords
        }
        settings.canadianEhOfferAnswered = true
        DebugLogger.shared.info("CANADIAN_EH_OFFER answered keep=\(keep) surface=\(surface)", source: "CanadianEh")
        return fillerWords
    }
}
