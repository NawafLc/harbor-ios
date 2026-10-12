import Foundation

/// Same rules as your Harbor PC patch (harbor-english-dub.js, badge-only version).
enum DubDetector {
    enum Result {
        /// Release name/description says it carries an English dub.
        case yes
        /// English + Japanese listed, no explicit dub tag.
        case likely
    }

    private static func rx(_ pattern: String) -> NSRegularExpression {
        // Patterns are constants; a failure here is a programming error.
        try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    private static let explicit = rx(#"\b(?:eng(?:lish)?\W{0,3}dub(?:bed|s)?|dub(?:bed)?\W{0,3}(?:in\W)?eng(?:lish)?|en\W?dub|english\W{0,3}audio|audio\W{0,3}eng(?:lish)?)\b"#)
    private static let dubbed = rx(#"\b(?:dub|dubs|dubbed)\b"#)
    private static let dual = rx(#"\b(?:dual|multi)\W{0,3}(?:audio|aud|lang(?:uage)?s?)\b|\bdual\b(?!\W{0,3}sub)|\bmulti\b(?!\W{0,3}sub)"#)
    private static let enJa = rx(#"\b(?:en|eng|english)\s*[+&/|,]\s*(?:ja|jp|jpn|jap|japanese)\b|\b(?:ja|jp|jpn|jap|japanese)\s*[+&/|,]\s*(?:en|eng|english)\b"#)
    private static let enSubOnly = rx(#"\beng(?:lish)?\W{0,3}(?:sub|subs|subbed|subtitles?|subtitled|softsubs?|hardsubs?)\b"#)
    private static let langRx = rx(#"\b(ENG(?:LISH)?|JPN|JAPANESE|JAP|KOR(?:EAN)?|CHN|CHI(?:NESE)?|MANDARIN|SPA(?:NISH)?|ESP|LATINO|ITA(?:LIAN)?|GER(?:MAN)?|DEU|FRA|FRENCH|POR(?:TUGUESE)?|RUS(?:SIAN)?|HIN(?:DI)?|ARA(?:BIC)?|MULTI|DUAL)\b"#)

    private static let langTokens: [String: String] = [
        "ENG": "English", "ENGLISH": "English", "JPN": "Japanese", "JAPANESE": "Japanese", "JAP": "Japanese",
        "KOR": "Korean", "KOREAN": "Korean", "CHN": "Chinese", "CHI": "Chinese", "CHINESE": "Chinese", "MANDARIN": "Chinese",
        "SPA": "Spanish", "SPANISH": "Spanish", "ESP": "Spanish", "LATINO": "Spanish", "ITA": "Italian", "ITALIAN": "Italian",
        "GER": "German", "GERMAN": "German", "DEU": "German", "FRA": "French", "FRENCH": "French", "POR": "Portuguese",
        "PORTUGUESE": "Portuguese", "RUS": "Russian", "RUSSIAN": "Russian", "HIN": "Hindi", "HINDI": "Hindi",
        "ARA": "Arabic", "ARABIC": "Arabic",
    ]

    private static let flagLangs: [String: String] = [
        "US": "English", "GB": "English", "CA": "English", "AU": "English", "NZ": "English", "IE": "English",
        "JP": "Japanese", "KR": "Korean", "CN": "Chinese", "HK": "Chinese", "TW": "Chinese", "ES": "Spanish", "MX": "Spanish",
        "IT": "Italian", "DE": "German", "FR": "French", "PT": "Portuguese", "BR": "Portuguese", "RU": "Russian", "IN": "Hindi",
        "SA": "Arabic",
    ]

    private static func matches(_ r: NSRegularExpression, _ text: String) -> Bool {
        r.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    static func languages(in text: String) -> Set<String> {
        var out = Set<String>()
        for m in langRx.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let r = Range(m.range, in: text) else { continue }
            out.insert(langTokens[text[r].uppercased()] ?? "Multi")
        }
        // Flag emoji (regional indicator pairs) like 🇺🇸 🇯🇵
        let scalars = Array(text.unicodeScalars)
        var i = 0
        while i + 1 < scalars.count {
            let a = scalars[i].value, b = scalars[i + 1].value
            if (0x1F1E6...0x1F1FF).contains(a) && (0x1F1E6...0x1F1FF).contains(b) {
                let first = Character(Unicode.Scalar(UInt8(a - 0x1F1E6 + 65)))
                let second = Character(Unicode.Scalar(UInt8(b - 0x1F1E6 + 65)))
                let cc = String([first, second])
                if let lang = flagLangs[cc] { out.insert(lang) }
                i += 2
            } else {
                i += 1
            }
        }
        return out
    }

    static func detect(_ stream: StreamItem) -> Result? {
        let raw = stream.allText
        let text = raw.replacingOccurrences(of: "[._]", with: " ", options: .regularExpression)
        let langs = languages(in: raw)
        let hasEn = langs.contains("English")
        let hasJa = langs.contains("Japanese")
        let onlyNeutral = langs.allSatisfy { $0 == "Japanese" || $0 == "Multi" }

        if matches(explicit, text) { return .yes }
        if matches(dubbed, text) && (hasEn || onlyNeutral) { return .yes }
        if (matches(dual, text) || matches(enJa, text)) && (hasEn || onlyNeutral) { return .yes }
        if hasEn && hasJa && !matches(enSubOnly, text) { return .likely }
        return nil
    }
}
