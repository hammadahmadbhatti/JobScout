import Foundation

/// The country a search covers. JobScout searches whole countries (no city,
/// no radius): LinkedIn by country name, Indeed through that country's
/// national site, and the German boards only when the country is Germany.
public struct Country: Hashable, Identifiable, Sendable {
    public var id: String { code }
    /// ISO 3166-1 alpha-2 code, e.g. "DE".
    public let code: String
    /// English name; also what LinkedIn receives as the location.
    public let name: String
    public let flag: String
    /// Indeed national subdomain ("de" → de.indeed.com, "www" for the US).
    public let indeedSubdomain: String
    /// Other spellings seen in job locations (native names, "UK", …).
    public let aliases: [String]
    /// Largest cities — used to place jobs whose location names only a city.
    public let cities: [String]
    /// Extra codes that mean this country at the end of a location ("UK").
    public let extraCodes: [String]

    public init(
        code: String, name: String, flag: String, indeedSubdomain: String,
        aliases: [String] = [], cities: [String] = [], extraCodes: [String] = []
    ) {
        self.code = code
        self.name = name
        self.flag = flag
        self.indeedSubdomain = indeedSubdomain
        self.aliases = aliases
        self.cities = cities
        self.extraCodes = extraCodes
    }

    public var label: String { "\(flag) \(name)" }
}

public extension Country {
    static let germany = Countries.byCode["DE"]!
}

public enum Countries {
    public static let all: [Country] = [
        Country(code: "DE", name: "Germany", flag: "🇩🇪", indeedSubdomain: "de",
                aliases: ["Deutschland", "Federal Republic of Germany"],
                cities: ["Berlin", "Hamburg", "München", "Munich", "Köln", "Cologne",
                         "Frankfurt", "Stuttgart", "Düsseldorf", "Leipzig", "Dortmund",
                         "Essen", "Bremen", "Dresden", "Hannover", "Hanover", "Nürnberg",
                         "Nuremberg", "Duisburg", "Bochum", "Bonn", "Mannheim", "Karlsruhe",
                         "Münster", "Augsburg", "Wiesbaden", "Potsdam", "Heidelberg",
                         "Freiburg", "Darmstadt", "Regensburg", "Ingolstadt", "Wolfsburg",
                         "Kiel", "Lübeck", "Mainz", "Aachen", "Erlangen", "Walldorf",
                         "Bielefeld", "Braunschweig", "Magdeburg", "Rostock", "Jena"]),
        Country(code: "AT", name: "Austria", flag: "🇦🇹", indeedSubdomain: "at",
                aliases: ["Österreich"],
                cities: ["Wien", "Vienna", "Graz", "Linz", "Salzburg", "Innsbruck",
                         "Klagenfurt", "Villach", "Wels", "St. Pölten"]),
        Country(code: "CH", name: "Switzerland", flag: "🇨🇭", indeedSubdomain: "ch",
                aliases: ["Schweiz", "Suisse", "Svizzera"],
                cities: ["Zürich", "Zurich", "Genf", "Geneva", "Genève", "Basel", "Bern",
                         "Lausanne", "Luzern", "Lucerne", "Zug", "Winterthur",
                         "St. Gallen", "Lugano"]),
        Country(code: "NL", name: "Netherlands", flag: "🇳🇱", indeedSubdomain: "nl",
                aliases: ["Nederland", "The Netherlands", "Holland", "Niederlande"],
                cities: ["Amsterdam", "Rotterdam", "The Hague", "Den Haag", "Utrecht",
                         "Eindhoven", "Groningen", "Leiden", "Delft", "Haarlem", "Tilburg"]),
        Country(code: "BE", name: "Belgium", flag: "🇧🇪", indeedSubdomain: "be",
                aliases: ["België", "Belgique", "Belgien"],
                cities: ["Brussels", "Bruxelles", "Brussel", "Antwerp", "Antwerpen",
                         "Ghent", "Gent", "Leuven", "Liège", "Mechelen"]),
        Country(code: "LU", name: "Luxembourg", flag: "🇱🇺", indeedSubdomain: "lu",
                aliases: ["Luxemburg"],
                cities: ["Esch-sur-Alzette", "Differdange", "Kirchberg"]),
        Country(code: "IE", name: "Ireland", flag: "🇮🇪", indeedSubdomain: "ie",
                aliases: ["Éire", "Irland", "Republic of Ireland"],
                cities: ["Dublin", "Cork", "Galway", "Limerick", "Waterford"]),
        Country(code: "GB", name: "United Kingdom", flag: "🇬🇧", indeedSubdomain: "uk",
                aliases: ["Great Britain", "England", "Scotland", "Wales",
                          "Northern Ireland", "Vereinigtes Königreich"],
                cities: ["London", "Manchester", "Birmingham", "Edinburgh", "Glasgow",
                         "Leeds", "Bristol", "Liverpool", "Cambridge", "Oxford",
                         "Belfast", "Cardiff", "Newcastle", "Sheffield", "Nottingham",
                         "Reading", "Brighton"],
                extraCodes: ["UK"]),
        Country(code: "FR", name: "France", flag: "🇫🇷", indeedSubdomain: "fr",
                aliases: ["Frankreich"],
                cities: ["Paris", "Lyon", "Marseille", "Toulouse", "Nice", "Nantes",
                         "Bordeaux", "Lille", "Strasbourg", "Montpellier"]),
        Country(code: "ES", name: "Spain", flag: "🇪🇸", indeedSubdomain: "es",
                aliases: ["España", "Spanien"],
                cities: ["Madrid", "Barcelona", "Valencia", "Seville", "Sevilla",
                         "Málaga", "Bilbao", "Palma"]),
        Country(code: "PT", name: "Portugal", flag: "🇵🇹", indeedSubdomain: "pt",
                cities: ["Lisbon", "Lisboa", "Porto", "Braga", "Coimbra"]),
        Country(code: "IT", name: "Italy", flag: "🇮🇹", indeedSubdomain: "it",
                aliases: ["Italia", "Italien"],
                cities: ["Rome", "Roma", "Milan", "Milano", "Turin", "Torino", "Naples",
                         "Napoli", "Bologna", "Florence", "Firenze"]),
        Country(code: "PL", name: "Poland", flag: "🇵🇱", indeedSubdomain: "pl",
                aliases: ["Polska", "Polen"],
                cities: ["Warsaw", "Warszawa", "Kraków", "Krakow", "Wrocław", "Gdańsk",
                         "Poznań", "Łódź", "Katowice"]),
        Country(code: "CZ", name: "Czechia", flag: "🇨🇿", indeedSubdomain: "cz",
                aliases: ["Czech Republic", "Česko", "Tschechien"],
                cities: ["Prague", "Praha", "Brno", "Ostrava"]),
        Country(code: "SE", name: "Sweden", flag: "🇸🇪", indeedSubdomain: "se",
                aliases: ["Sverige", "Schweden"],
                cities: ["Stockholm", "Gothenburg", "Göteborg", "Malmö", "Uppsala"]),
        Country(code: "DK", name: "Denmark", flag: "🇩🇰", indeedSubdomain: "dk",
                aliases: ["Danmark", "Dänemark"],
                cities: ["Copenhagen", "København", "Aarhus", "Odense"]),
        Country(code: "NO", name: "Norway", flag: "🇳🇴", indeedSubdomain: "no",
                aliases: ["Norge", "Norwegen"],
                cities: ["Oslo", "Bergen", "Trondheim", "Stavanger"]),
        Country(code: "FI", name: "Finland", flag: "🇫🇮", indeedSubdomain: "fi",
                aliases: ["Suomi", "Finnland"],
                cities: ["Helsinki", "Espoo", "Tampere", "Turku", "Oulu"]),
        Country(code: "US", name: "United States", flag: "🇺🇸", indeedSubdomain: "www",
                aliases: ["United States of America", "USA", "U.S.", "U.S.A."],
                cities: ["New York", "San Francisco", "Seattle", "Boston", "Chicago",
                         "Austin", "Los Angeles", "Washington", "Atlanta", "Denver",
                         "Dallas", "Houston", "Miami", "San Diego", "San Jose"],
                extraCodes: ["USA"]),
        Country(code: "CA", name: "Canada", flag: "🇨🇦", indeedSubdomain: "ca",
                aliases: ["Kanada"],
                cities: ["Toronto", "Vancouver", "Montreal", "Montréal", "Ottawa",
                         "Calgary", "Edmonton", "Waterloo"]),
        Country(code: "AU", name: "Australia", flag: "🇦🇺", indeedSubdomain: "au",
                aliases: ["Australien"],
                cities: ["Sydney", "Melbourne", "Brisbane", "Perth", "Adelaide", "Canberra"]),
        Country(code: "NZ", name: "New Zealand", flag: "🇳🇿", indeedSubdomain: "nz",
                aliases: ["Neuseeland"],
                cities: ["Auckland", "Wellington", "Christchurch"]),
        Country(code: "AE", name: "United Arab Emirates", flag: "🇦🇪", indeedSubdomain: "ae",
                aliases: ["UAE", "Emirates"],
                cities: ["Dubai", "Abu Dhabi", "Sharjah"]),
        Country(code: "SG", name: "Singapore", flag: "🇸🇬", indeedSubdomain: "sg",
                aliases: ["Singapur"]),
        Country(code: "IN", name: "India", flag: "🇮🇳", indeedSubdomain: "in",
                aliases: ["Indien"],
                cities: ["Bengaluru", "Bangalore", "Mumbai", "Delhi", "New Delhi",
                         "Hyderabad", "Pune", "Chennai", "Gurgaon", "Gurugram", "Noida"]),
        Country(code: "PK", name: "Pakistan", flag: "🇵🇰", indeedSubdomain: "pk",
                cities: ["Karachi", "Lahore", "Islamabad", "Rawalpindi", "Faisalabad"]),
    ]

    public static let byCode: [String: Country] =
        Dictionary(uniqueKeysWithValues: all.map { ($0.code, $0) })

    public static func find(_ codeOrName: String) -> Country? {
        let q = codeOrName.trimmingCharacters(in: .whitespaces)
        if let c = byCode[q.uppercased()] { return c }
        return all.first { c in
            ([c.name] + c.aliases).contains { $0.caseInsensitiveCompare(q) == .orderedSame }
        }
    }

    public enum Placement: Sendable { case inCountry, elsewhere, unknown }

    /// Decides whether a free-text job location lies in `country`.
    ///
    /// Used for sources without a native country filter (Xing, career sites).
    /// Conservative: only a location that clearly names another country (or
    /// one of its big cities) counts as `elsewhere`; anything unclear passes.
    public static func place(_ location: String, in country: Country) -> Placement {
        let tokens = foldedTokens(location)
        guard !tokens.isEmpty else { return .unknown }
        let lastCode = location
            .components(separatedBy: CharacterSet.letters.inverted)
            .last(where: { !$0.isEmpty }) ?? ""

        func matches(_ c: Country) -> Bool {
            if lastCode.count >= 2, lastCode == lastCode.uppercased(),
               lastCode == c.code || c.extraCodes.contains(lastCode) {
                return true
            }
            return ([c.name] + c.aliases + c.cities).contains { phrase in
                containsPhrase(tokens, foldedTokens(phrase))
            }
        }

        if matches(country) { return .inCountry }
        if all.contains(where: { $0 != country && matches($0) }) { return .elsewhere }
        return .unknown
    }

    static func foldedTokens(_ s: String) -> [String] {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    static func containsPhrase(_ haystack: [String], _ needle: [String]) -> Bool {
        guard !needle.isEmpty, needle.count <= haystack.count else { return false }
        for start in 0...(haystack.count - needle.count)
        where Array(haystack[start..<start + needle.count]) == needle {
            return true
        }
        return false
    }
}
