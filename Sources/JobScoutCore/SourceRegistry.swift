import Foundation

/// Central place both the app and the CLI use to construct sources.
public enum SourceRegistry {
    public static let platformNames = [
        "linkedin", "arbeitsagentur", "indeed", "xing", "stepstone", "career-site",
    ]

    public static func displayName(_ source: String) -> String {
        switch source {
        case "linkedin": return "LinkedIn"
        case "arbeitsagentur": return "Arbeitsagentur"
        case "indeed": return "Indeed"
        case "xing": return "Xing"
        case "stepstone": return "StepStone"
        case "career-site": return "Company sites"
        default: return source.capitalized
        }
    }

    public static func make(
        names: [String],
        watchlist: [ATSCompany] = [],
        indeedCountry: String = "DE"
    ) -> [any JobSource] {
        names.compactMap { name in
            switch name {
            case "linkedin": return LinkedInSource()
            case "arbeitsagentur": return ArbeitsagenturSource()
            case "indeed": return IndeedSource(country: indeedCountry)
            case "xing": return XingSource()
            case "stepstone": return StepStoneSource()
            case "career-site": return CompanyWatchlistSource(companies: watchlist)
            default: return nil
            }
        }
    }
}
