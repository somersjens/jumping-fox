//
//  SpokenMath.swift
//  Jumping Fox
//
//  Compact, language-native wording for the sums read by AppAudio.
//

import Foundation

/// Converts the language-neutral question shown by the game into a short
/// utterance. Numerals deliberately remain numerals: the selected system voice
/// already knows how to pronounce them in its own language.
enum SpokenMath {
    struct Lexicon {
        let plus: String
        let minus: String
        let times: String
        let dividedBy: String
        let percentPattern: String
        let percentOfPattern: String
        let equals: String
        let unknown: String

        init(_ plus: String, _ minus: String, _ times: String, _ dividedBy: String,
             _ percentPattern: String, _ percentOfPattern: String,
             _ equals: String, _ unknown: String) {
            self.plus = plus
            self.minus = minus
            self.times = times
            self.dividedBy = dividedBy
            self.percentPattern = percentPattern
            self.percentOfPattern = percentOfPattern
            self.equals = equals
            self.unknown = unknown
        }

        func percent(_ value: String) -> String {
            percentPattern.replacingOccurrences(of: "%p", with: value)
        }

        func percentOf(_ value: String, whole: String) -> String {
            percentOfPattern
                .replacingOccurrences(of: "%p", with: value)
                .replacingOccurrences(of: "%w", with: whole)
        }
    }

    /// Languages for which Apple currently supplies an AVSpeech voice on its
    /// platforms and which are also present in the app. A runtime voice check
    /// still decides whether speech is enabled on the particular device.
    static let lexicons: [String: Lexicon] = [
        "ar": .init("زائد", "ناقص", "ضرب", "مقسوم على", "%p بالمئة", "%p بالمئة من %w", "يساوي", "كم"),
        "bg": .init("плюс", "минус", "по", "делено на", "%p процента", "%p процента от %w", "равно", "колко"),
        "bn": .init("যোগ", "বিয়োগ", "গুণ", "ভাগ", "%p শতাংশ", "%w-এর %p শতাংশ", "সমান", "কত"),
        "ca": .init("més", "menys", "per", "dividit per", "%p per cent", "%p per cent de %w", "és igual a", "quant"),
        "cs": .init("plus", "mínus", "krát", "děleno", "%p procent", "%p procent z %w", "rovná se", "kolik"),
        "da": .init("plus", "minus", "gange", "divideret med", "%p procent", "%p procent af %w", "er lig med", "hvor mange"),
        "de": .init("plus", "minus", "mal", "geteilt durch", "%p Prozent", "%p Prozent von %w", "ist gleich", "wie viel"),
        "el": .init("συν", "μείον", "επί", "διά", "%p τοις εκατό", "%p τοις εκατό του %w", "ίσον", "πόσο"),
        "en": .init("plus", "minus", "times", "divided by", "%p percent", "%p percent of %w", "is", "how many"),
        "es": .init("más", "menos", "por", "dividido entre", "%p por ciento", "%p por ciento de %w", "es igual a", "cuánto"),
        "eu": .init("gehi", "ken", "bider", "zati", "ehuneko %p", "%w-ren ehuneko %p", "berdin", "zenbat"),
        "fa": .init("به‌علاوه", "منهای", "ضربدر", "تقسیم بر", "%p درصد", "%p درصدِ %w", "مساوی", "چند"),
        "fi": .init("plus", "miinus", "kertaa", "jaettuna", "%p prosenttia", "%p prosenttia luvusta %w", "on yhtä kuin", "kuinka monta"),
        "fr": .init("plus", "moins", "fois", "divisé par", "%p pour cent", "%p pour cent de %w", "égale", "combien"),
        "gl": .init("máis", "menos", "por", "dividido entre", "%p por cento", "%p por cento de %w", "igual a", "canto"),
        "he": .init("ועוד", "פחות", "כפול", "חלקי", "%p אחוזים", "%p אחוזים מתוך %w", "שווה", "כמה"),
        "hi": .init("प्लस", "माइनस", "गुणा", "भाग", "%p प्रतिशत", "%w का %p प्रतिशत", "बराबर", "कितना"),
        "hr": .init("plus", "minus", "puta", "podijeljeno s", "%p posto", "%p posto od %w", "jednako", "koliko"),
        "hu": .init("plusz", "mínusz", "szor", "osztva", "%p százalék", "%w %p százaléka", "egyenlő", "mennyi"),
        "id": .init("tambah", "kurang", "kali", "dibagi", "%p persen", "%p persen dari %w", "sama dengan", "berapa"),
        "it": .init("più", "meno", "per", "diviso", "%p per cento", "%p per cento di %w", "uguale", "quanto"),
        "ja": .init("たす", "ひく", "かける", "わる", "%p パーセント", "%w の %p パーセント", "イコール", "いくつ"),
        "kn": .init("ಕೂಡಿಸು", "ಕಳೆ", "ಗುಣಿಸು", "ಭಾಗಿಸು", "%p ಶೇಕಡಾ", "%w ರ %p ಶೇಕಡಾ", "ಸಮ", "ಎಷ್ಟು"),
        "ko": .init("더하기", "빼기", "곱하기", "나누기", "%p 퍼센트", "%w 의 %p 퍼센트", "같다", "얼마"),
        "ms": .init("tambah", "tolak", "darab", "bahagi", "%p peratus", "%p peratus daripada %w", "sama dengan", "berapa"),
        "mr": .init("अधिक", "वजा", "गुणिले", "भागिले", "%p टक्के", "%w चे %p टक्के", "बरोबर", "किती"),
        "nl": .init("plus", "min", "keer", "gedeeld door", "%p procent", "%p procent van %w", "is", "hoeveel"),
        "no": .init("pluss", "minus", "ganger", "delt på", "%p prosent", "%p prosent av %w", "er lik", "hvor mange"),
        "pl": .init("plus", "minus", "razy", "podzielone przez", "%p procent", "%p procent z %w", "równa się", "ile"),
        "pt": .init("mais", "menos", "vezes", "dividido por", "%p por cento", "%p por cento de %w", "é igual a", "quanto"),
        "ro": .init("plus", "minus", "ori", "împărțit la", "%p la sută", "%p la sută din %w", "egal", "cât"),
        "ru": .init("плюс", "минус", "умножить на", "разделить на", "%p процентов", "%p процентов от %w", "равно", "сколько"),
        "sk": .init("plus", "mínus", "krát", "delené", "%p percent", "%p percent z %w", "rovná sa", "koľko"),
        "sl": .init("plus", "minus", "krat", "deljeno z", "%p odstotkov", "%p odstotkov od %w", "je enako", "koliko"),
        "sv": .init("plus", "minus", "gånger", "delat med", "%p procent", "%p procent av %w", "är lika med", "hur många"),
        "ta": .init("கூட்டல்", "கழித்தல்", "பெருக்கல்", "வகுத்தல்", "%p சதவீதம்", "%w இன் %p சதவீதம்", "சமம்", "எவ்வளவு"),
        "te": .init("కూడిక", "తీసివేత", "గుణించు", "భాగించు", "%p శాతం", "%w యొక్క %p శాతం", "సమానం", "ఎంత"),
        "th": .init("บวก", "ลบ", "คูณ", "หาร", "%p เปอร์เซ็นต์", "%p เปอร์เซ็นต์ของ %w", "เท่ากับ", "เท่าไร"),
        "tr": .init("artı", "eksi", "çarpı", "bölü", "yüzde %p", "%w sayısının yüzde %p'i", "eşittir", "kaç"),
        "uk": .init("плюс", "мінус", "помножити на", "поділити на", "%p відсотків", "%p відсотків від %w", "дорівнює", "скільки"),
        "vi": .init("cộng", "trừ", "nhân", "chia", "%p phần trăm", "%p phần trăm của %w", "bằng", "bao nhiêu"),
        "zh": .init("加", "减", "乘", "除以", "百分之 %p", "%w 的百分之 %p", "等于", "多少")
    ]

    /// A fraction is a part of a whole, not a division instruction. These
    /// compact patterns deliberately avoid language-specific ordinal
    /// inflection while still sounding natural. `%n` is the numerator and
    /// `%d` the denominator. Dutch is handled separately below because its
    /// short school form (“1 twintigste”) is both clear and productive.
    private static let fractionPatterns: [String: String] = [
        "ar": "%n من %d أجزاء",
        "bg": "%n от %d части",
        "bn": "%d ভাগের %n ভাগ",
        "ca": "%n de %d parts",
        "cs": "%n z %d dílů",
        "da": "%n ud af %d dele",
        "de": "%n von %d Teilen",
        "el": "%n από %d μέρη",
        "en": "%n of %d parts",
        "es": "%n de %d partes",
        "eu": "%d zatitik %n",
        "fa": "%n قسمت از %d",
        "fi": "%n osaa %d:stä",
        "fr": "%n sur %d",
        "gl": "%n de %d partes",
        "he": "%n מתוך %d חלקים",
        "hi": "%d में से %n भाग",
        "hr": "%n od %d dijelova",
        "hu": "%d-ből %n rész",
        "id": "%n dari %d bagian",
        "it": "%n su %d parti",
        "ja": "%d 分の %n",
        "kn": "%d ರಲ್ಲಿ %n ಭಾಗ",
        "ko": "%d 분의 %n",
        "ms": "%n daripada %d bahagian",
        "mr": "%d पैकी %n भाग",
        "no": "%n av %d deler",
        "pl": "%n z %d części",
        "pt": "%n de %d partes",
        "ro": "%n din %d părți",
        "ru": "%n из %d частей",
        "sk": "%n z %d častí",
        "sl": "%n od %d delov",
        "sv": "%n av %d delar",
        "ta": "%d இல் %n பங்கு",
        "te": "%d లో %n భాగం",
        "th": "%n ส่วนจาก %d ส่วน",
        "tr": "%d parçadan %n",
        "uk": "%n з %d частин",
        "vi": "%n phần trong %d phần",
        "zh": "%d 分之 %n"
    ]

    static var fractionPatternLanguageCodes: Set<String> {
        Set(fractionPatterns.keys)
    }

    static func text(for prompt: String, languageCode: String) -> String? {
        guard let lexicon = lexicons[languageCode] else { return nil }
        let sides = prompt.components(separatedBy: "=")
        if sides.count == 2 {
            let lhs = expression(sides[0], languageCode: languageCode, lexicon: lexicon)
            let rhs = sides[1].trimmingCharacters(in: .whitespaces)
            if rhs == "?" {
                return lhs
            }
            return "\(lhs) \(lexicon.equals) \(expression(rhs, languageCode: languageCode, lexicon: lexicon))"
        }
        return expression(prompt, languageCode: languageCode, lexicon: lexicon)
    }

    private static func expression(_ expression: String, languageCode: String,
                                   lexicon: Lexicon) -> String {
        let tokens = expression.split(separator: " ").map(String.init)

        // Percent questions are said in the natural order of the language,
        // rather than literally reading “percent times”.
        if tokens.count == 3,
           tokens[0].hasSuffix("%"),
           tokens[1] == "×" {
            let percent = String(tokens[0].dropLast())
            return lexicon.percentOf(number(percent, lexicon: lexicon),
                                     whole: term(tokens[2], languageCode: languageCode,
                                                 lexicon: lexicon))
        }

        return tokens.map { token in
            switch token {
            case "+": return lexicon.plus
            case "−", "-": return lexicon.minus
            case "×": return lexicon.times
            case "÷": return lexicon.dividedBy
            case "=": return lexicon.equals
            default: return term(token, languageCode: languageCode, lexicon: lexicon)
            }
        }.joined(separator: " ")
    }

    private static func term(_ token: String, languageCode: String,
                             lexicon: Lexicon) -> String {
        if token.hasSuffix("%") {
            return lexicon.percent(number(String(token.dropLast()), lexicon: lexicon))
        }
        if token.contains("/") {
            let parts = token.components(separatedBy: "/")
            if parts.count == 2 {
                return fraction(numerator: number(parts[0], lexicon: lexicon),
                                denominator: number(parts[1], lexicon: lexicon),
                                languageCode: languageCode)
            }
        }
        return number(token, lexicon: lexicon)
    }

    private static func fraction(numerator: String, denominator: String,
                                 languageCode: String) -> String {
        if languageCode == "nl" {
            if numerator == lexicons["nl"]?.unknown {
                return "\(numerator) \(dutchOrdinal(denominator))n"
            }
            return "\(numerator) \(dutchOrdinal(denominator))"
        }
        let pattern = fractionPatterns[languageCode] ?? "%n/%d"
        return pattern
            .replacingOccurrences(of: "%n", with: numerator)
            .replacingOccurrences(of: "%d", with: denominator)
    }

    /// Numeric ordinal spelling keeps even advanced denominators such as 128
    /// short while prompting the Dutch voice to say “honderdachtentwintigste”.
    private static func dutchOrdinal(_ denominator: String) -> String {
        guard denominator != "hoeveel", let value = Int(denominator) else {
            return denominator
        }
        let suffix = value == 8 || value >= 20 ? "ste" : "de"
        return "\(value)\(suffix)"
    }

    private static func number(_ text: String, lexicon: Lexicon) -> String {
        text == "?" ? lexicon.unknown : text
    }
}
