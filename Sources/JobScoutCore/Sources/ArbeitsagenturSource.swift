import Foundation

/// Bundesagentur für Arbeit Jobsuche — official public REST API (v6).
///
/// This is the same API the official site (jobsuche.arbeitsagentur.de) calls.
/// The `X-API-Key` is the public client id embedded in that site's own
/// frontend config, not a secret. Verified working 2026-10.
/// Germany only — searching without `wo` covers the whole country.
public struct ArbeitsagenturSource: JobSource {
    public let name = "arbeitsagentur"

    public init() {}

    static let base = "https://rest.arbeitsagentur.de/jobboerse/jobsuche-service/pc/v6/jobs"
    static let apiKey = "jobboerse-jobsuche"

    struct Response: Decodable {
        let ergebnisliste: [Item]?
        let maxErgebnisse: JSONNumber?
    }

    // maxErgebnisse arrives as number or string depending on endpoint mood.
    struct JSONNumber: Decodable {
        let value: Int
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let i = try? c.decode(Int.self) { value = i }
            else if let s = try? c.decode(String.self) { value = Int(s) ?? 0 }
            else { value = 0 }
        }
    }

    struct Item: Decodable {
        let stellenangebotsTitel: String?
        let hauptberuf: String?
        let firma: String?
        let referenznummer: String?
        let externeURL: String?
        let aenderungsdatum: String?
        let datumErsteVeroeffentlichung: String?
        let arbeitszeitVollzeit: Bool?
        let arbeitszeitTeilzeitFlexibel: Bool?
        let arbeitszeitTeilzeitVormittag: Bool?
        let arbeitszeitTeilzeitNachmittag: Bool?
        let arbeitszeitTeilzeitAbend: Bool?
        let istGeringfuegigeBeschaeftigung: Bool?
        let homeofficemoeglich: Bool?
        let stellenlokationen: [Lokation]?
        let veroeffentlichungszeitraum: Zeitraum?
    }

    struct Lokation: Decodable {
        let adresse: Adresse?
    }
    struct Adresse: Decodable {
        let plz: String?
        let ort: String?
        let region: String?
    }
    struct Zeitraum: Decodable { let von: String? }

    func params(_ query: SearchQuery, page: Int, size: Int) -> [(String, String)] {
        var p: [(String, String)] = [
            ("page", String(page)),
            ("size", String(size)),
        ]
        if !query.keywords.isEmpty { p.append(("was", query.keywords)) }
        if let days = query.datePosted.days {
            p.append(("veroeffentlichtseit", String(days)))
        }
        var az: [String] = []
        if query.jobTypes.contains(.fullTime) { az.append("vz") }
        if query.jobTypes.contains(.partTime) { az.append("tz") }
        if query.jobTypes.contains(.miniJob) { az.append("mj") }
        if query.remote.contains(.remote) || query.remote.contains(.hybrid) {
            az.append("ho")
        }
        if !az.isEmpty { p.append(("arbeitszeit", az.joined(separator: ";"))) }
        if query.jobTypes.contains(.internship) && query.jobTypes.count == 1 {
            p.append(("angebotsart", "34")) // Praktikum/Trainee only
        } else {
            p.append(("angebotsart", "1")) // regular jobs
        }
        return p
    }

    func toJob(_ item: Item) -> Job? {
        let title = item.stellenangebotsTitel ?? item.hauptberuf ?? ""
        guard !title.isEmpty else { return nil }
        let adresse = item.stellenlokationen?.first?.adresse
        let location = [adresse?.plz, adresse?.ort]
            .compactMap { $0 }.joined(separator: " ")
        let refnr = item.referenznummer ?? ""
        let url: String
        if let ext = item.externeURL, !ext.isEmpty {
            url = ext
        } else {
            let encoded = refnr.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? refnr
            url = "https://www.arbeitsagentur.de/jobsuche/jobdetail/\(encoded)"
        }
        let rawDate = item.datumErsteVeroeffentlichung
            ?? item.veroeffentlichungszeitraum?.von
            ?? item.aenderungsdatum ?? ""

        var types: [String] = []
        if item.arbeitszeitVollzeit == true { types.append("Vollzeit") }
        let teilzeit = [
            item.arbeitszeitTeilzeitFlexibel, item.arbeitszeitTeilzeitVormittag,
            item.arbeitszeitTeilzeitNachmittag, item.arbeitszeitTeilzeitAbend,
        ].contains(true)
        if teilzeit { types.append("Teilzeit") }
        if item.istGeringfuegigeBeschaeftigung == true { types.append("Minijob") }

        return Job(
            source: name,
            jobID: refnr.isEmpty ? title : refnr,
            title: title,
            company: item.firma ?? "",
            location: location,
            url: url,
            postedDateRaw: rawDate,
            posted: DateParsing.parse(rawDate),
            remote: item.homeofficemoeglich == true ? "Homeoffice möglich" : "",
            employmentType: types.joined(separator: ", ")
        )
    }

    public func search(_ query: SearchQuery) async throws -> [Job] {
        var jobs: [Job] = []
        var page = 1
        while jobs.count < query.limit && page <= 10 {
            let size = min(query.limit - jobs.count, 100)
            let url = HTTP.url(Self.base, params(query, page: page, size: size))
            let data = try await HTTP.get(url, headers: ["X-API-Key": Self.apiKey])
            let resp = try JSONDecoder().decode(Response.self, from: data)
            let items = resp.ergebnisliste ?? []
            if items.isEmpty { break }
            jobs.append(contentsOf: items.compactMap(toJob))
            if items.count < size { break }
            page += 1
        }
        return Array(jobs.prefix(query.limit))
    }
}
