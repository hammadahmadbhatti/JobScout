import Foundation
import NaturalLanguage

/// Language detection for job postings — JobScout is built for people looking
/// for English-speaking jobs, so the question is always "is this posting in
/// English?".
///
/// Evidence, strongest first:
///  1. the source's own language tag (Indeed reports one per job),
///  2. the full description (Apple's NLLanguageRecognizer is reliable on it),
///  3. the title. Titles are weak evidence: English postings in Germany carry
///     "(m/w/d)" and English job names ("Software Engineer") head plenty of
///     German postings. So a title can only prove German (German words or
///     umlauts); an English-looking title stays *unverified* until the
///     description is checked. Descriptions are told apart from all common
///     European languages, so a Dutch ad in the Netherlands counts as
///     not English just like a German one.
public enum LanguageDetector {
    public enum Verdict: String, Sendable {
        case english, notEnglish
        /// Title looks English, but nothing confirmed it yet.
        case unverified
    }

    /// Words that only appear in German-language titles.
    private static let germanWords: Set<String> = [
        "und", "für", "fur", "mit", "der", "die", "das", "bei", "im", "zur", "zum",
        "ab", "sofort", "oder", "als", "gesucht", "vollzeit", "teilzeit",
        "minijob", "aushilfe", "befristet", "unbefristet", "festanstellung",
        "mitarbeiter", "mitarbeiterin", "kaufmann", "kauffrau", "ausbildung",
        "praktikum", "praktikant", "praktikantin", "vertrieb", "fachkraft",
        "leiter", "leiterin", "leitung", "berater", "beraterin", "ingenieur",
        "ingenieurin", "entwickler", "entwicklerin", "buchhaltung", "einkauf",
        "sachbearbeiter", "sachbearbeiterin", "referent", "referentin",
        "werkstudent", "werkstudentin", "pflegefachkraft", "steuerfachangestellte",
        "geschäftsführer", "betreuung", "koch", "köchin", "kellner", "kellnerin",
        "verkäufer", "verkäuferin", "reinigungskraft", "küchenhilfe",
        "servicekraft", "fahrer", "fahrerin", "lagerhelfer", "lagermitarbeiter",
        "elektriker", "monteur", "erzieher", "erzieherin", "pfleger", "pflegerin",
        "assistenz", "projektleiter", "teamleiter", "bauleiter", "techniker",
        "technikerin", "kundenberater", "kundenservice", "softwareentwickler",
        "anwendungsentwickler", "systemadministrator", "informatiker",
        "wirtschaftsinformatiker", "bürokaufmann", "bürokauffrau",
    ]

    /// German compound stems ("Vertriebsmitarbeiter", "Lagerhelferin" …).
    private static let germanStems = [
        "mitarbeiter", "kaufmann", "kauffrau", "sachbearbeit", "fachkraft",
        "helfer", "entwickler", "berater", "leiter", "angestellte", "referent",
    ]

    /// What the title alone says.
    public static func titleVerdict(_ title: String) -> Verdict {
        if title.contains(where: { "äöüßÄÖÜ".contains($0) }) { return .notEnglish }
        let tokens = title.lowercased()
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { !$0.isEmpty }
        if tokens.contains(where: germanWords.contains) { return .notEnglish }
        let isCompound: (String) -> Bool = { t in
            t.count > 9 && germanStems.contains { t.hasSuffix($0) || t.hasSuffix($0 + "in") }
        }
        if tokens.contains(where: isCompound) {
            return .notEnglish
        }
        return .unverified
    }

    private static let candidates: [NLLanguage] = [
        .english, .german, .dutch, .french, .spanish, .italian, .portuguese,
        .polish, .swedish, .danish, .norwegian, .finnish, .czech,
    ]

    /// Language code of a longer text ("en", "de", "nl", …), or nil when it
    /// is too short to tell.
    public static func textLanguage(_ text: String) -> String? {
        let sample = String(text.prefix(2500))
        guard sample.count >= 120 else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = candidates
        recognizer.processString(sample)
        return recognizer.dominantLanguage?.rawValue
    }

    /// Best verdict for a job from what we have about it so far.
    /// `description` overrides the job's own (possibly empty) description.
    public static func verdict(for job: Job, description: String? = nil) -> Verdict {
        if let hint = job.languageHint, !hint.isEmpty {
            return hint.hasPrefix("en") ? .english : .notEnglish
        }
        let text = description ?? job.descriptionText
        if let lang = textLanguage(text) {
            return lang == "en" ? .english : .notEnglish
        }
        return titleVerdict(job.title)
    }

    /// English-only filter: drops postings known not to be English; unverified
    /// ones stay (the app verifies them against the full description).
    public static func englishOrUnverified(_ jobs: [Job]) -> [Job] {
        jobs.filter { verdict(for: $0) != .notEnglish }
    }
}

public extension Job {
    /// "en", "not-en", or "unconfirmed" (English title, description unchecked).
    var detectedLanguage: String {
        switch LanguageDetector.verdict(for: self) {
        case .english: return "en"
        case .notEnglish: return "not-en"
        case .unverified: return "unconfirmed"
        }
    }
}

/// Does an (English) posting ask for German? Read from the description, one
/// sentence at a time, so "fluent English; German is a plus" is not mistaken
/// for a German requirement.
public enum GermanRequirement: String, Codable, Sendable {
    case required, plus, notMentioned

    public var label: String {
        switch self {
        case .required: return "German required"
        case .plus: return "German is a plus"
        case .notMentioned: return "No German mentioned"
        }
    }

    private static let plusMarkers = [
        "a plus", "is a plus", "nice to have", "nice-to-have", "an advantage",
        "advantageous", "beneficial", "preferred", "a bonus", "bonus", "helpful",
        "desirable", "welcome", "appreciated", "not required", "not mandatory",
        "not a must", "no german", "optional", "would be great",
    ]
    private static let requiredMarkers = [
        "fluent", "fluency", "native", "proficien", "business level",
        "business-level", "c1", "c2", "b2", "b1", "required", "require",
        "must", "mandatory", "essential", "excellent", "very good", "strong",
        "good command", "command of", "knowledge of german", "german skills",
        "german language skills", "written and spoken", "spoken and written",
        "speak german", "speaking german",
    ]
    /// Sentences about German *courses* are perks, not requirements.
    private static let perkMarkers = [
        "course", "class", "lesson", "learn german", "learning german",
        "language training", "language school", "tuition", "teacher", "babbel",
    ]
    /// German-language phrasing that sometimes appears inside English ads.
    private static let germanPhrasing = [
        "deutschkenntnisse", "fließend deutsch", "fliessend deutsch",
        "verhandlungssicher", "sehr gute deutsch", "deutsch auf c1",
        "deutsch (c1", "deutsch c1",
    ]

    public static func detect(in description: String) -> (GermanRequirement, String?) {
        let sentences = description
            .components(separatedBy: CharacterSet(charactersIn: ".;!?\n•·|"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var found: (GermanRequirement, String)?
        for sentence in sentences {
            let low = sentence.lowercased()
            let mentionsGerman = low.range(of: #"\bgerman\b(?!y)"#, options: .regularExpression) != nil
            if !mentionsGerman {
                if germanPhrasing.contains(where: low.contains) {
                    return (.required, String(sentence.prefix(160)))
                }
                continue
            }
            if perkMarkers.contains(where: low.contains) { continue }
            if plusMarkers.contains(where: low.contains) {
                if found == nil { found = (.plus, String(sentence.prefix(160))) }
            } else if requiredMarkers.contains(where: low.contains) {
                return (.required, String(sentence.prefix(160)))
            }
        }
        if let f = found { return (f.0, f.1) }
        return (.notMentioned, nil)
    }
}

/// Heuristic experience-level post-filter for sources without a native filter.
///
/// Conservative on purpose: it only drops jobs whose titles clearly signal a
/// mismatching level, and keeps everything ambiguous.
public enum ExperienceFilter {
    private static let seniorMarkers = [
        "senior", "lead ", "principal", "head of", "director", "leitung",
        "leiter", "chef de", "geschäftsführ", "teamlead", "team lead", "sous chef",
    ]
    private static let entryMarkers = [
        "junior", "praktik", "intern ", "internship", "werkstudent", "trainee",
        "azubi", "auszubildende", "ausbildung", "einsteiger", "entry",
        "aushilfe", "student", "graduate",
    ]

    public static func apply(_ jobs: [Job], wanted: Set<ExperienceLevel>) -> [Job] {
        guard !wanted.isEmpty, wanted.count < ExperienceLevel.allCases.count else {
            return jobs
        }
        return jobs.filter { job in
            let t = " " + job.title.lowercased() + " "
            let isSenior = seniorMarkers.contains { t.contains($0) }
            let isEntry = entryMarkers.contains { t.contains($0) }
            if isSenior { return wanted.contains(.senior) }
            if isEntry { return wanted.contains(.entry) }
            return true // ambiguous titles always pass
        }
    }
}
