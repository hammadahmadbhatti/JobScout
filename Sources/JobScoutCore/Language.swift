import Foundation
import NaturalLanguage

/// Language detection for job postings (German vs English).
///
/// Job titles are short, so pure statistical detection is unreliable. We use
/// the same high-precision German markers as the proven Python engine (umlauts,
/// the ubiquitous "(m/w/d)" gender marker, common German job vocabulary) and
/// fall back to Apple's NLLanguageRecognizer for longer text.
public enum LanguageDetector {
    private static let germanMarkers = [
        "(m/w/d)", "(w/m/d)", "(m/w)", "(m/w/x)", "(m/w/d/x)", "(d/m/w)",
        "(gn)", "(m/f/d)", "m/w/d", "w/m/d",
    ]

    private static let germanWords: Set<String> = [
        "und", "für", "mit", "der", "die", "das", "bei", "im", "zur", "zum",
        "entwickler", "mitarbeiter", "mitarbeiterin", "kaufmann", "kauffrau",
        "ausbildung", "praktikum", "praktikant", "vertrieb", "fachkraft",
        "leiter", "leiterin", "berater", "beraterin", "ingenieur",
        "buchhaltung", "einkauf", "personal", "gehalt", "stelle", "bewerbung",
        "werkstudent", "pflegefachkraft", "steuerfachangestellte", "vollzeit",
        "teilzeit", "geschäftsführer", "betreuung", "koch", "köchin",
        "kellner", "kellnerin", "verkäufer", "verkäuferin", "reinigungskraft",
        "aushilfe", "gesucht", "küchenhilfe", "servicekraft", "fahrer",
    ]

    public static func isGerman(_ text: String) -> Bool {
        if text.contains(where: { "äöüßÄÖÜ".contains($0) }) { return true }
        let low = text.lowercased()
        if germanMarkers.contains(where: { low.contains($0) }) { return true }
        let tokens = Set(
            low.components(separatedBy: CharacterSet.letters.inverted)
                .filter { !$0.isEmpty }
        )
        if !tokens.isDisjoint(with: germanWords) { return true }
        // Statistical fallback helps on longer, marker-free text.
        if text.count > 60 {
            let recognizer = NLLanguageRecognizer()
            recognizer.languageConstraints = [.german, .english]
            recognizer.processString(String(text.prefix(400)))
            return recognizer.dominantLanguage == .german
        }
        return false
    }

    /// Returns "de" or "en".
    public static func detect(_ text: String) -> String {
        isGerman(text) ? "de" : "en"
    }

    /// Keep only jobs whose detected language is wanted (empty = keep all).
    public static func filter(_ jobs: [Job], languages: Set<String>) -> [Job] {
        guard !languages.isEmpty else { return jobs }
        return jobs.filter { languages.contains(detect($0.title)) }
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
        "aushilfe", "student",
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
