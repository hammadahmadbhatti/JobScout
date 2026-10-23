import Foundation

/// Indeed — the mobile app's public GraphQL API (no login, no paid key).
///
/// Same technique as the open-source JobSpy project: the request carries the
/// Indeed mobile app's embedded API key, which is public in every app install.
/// Best-effort: Indeed can rotate the key; if that happens the source reports
/// an honest error instead of fake results.
public struct IndeedSource: JobSource {
    public let name = "indeed"

    public init() {}

    static let apiURL = URL(string: "https://apis.indeed.com/graphql")!
    static let apiKey = "161092c2017b5bbab13edb12461a62d5a833871e7cad6d9d475304573de67ac8"

    static let jobTypeKeys: [JobType: String] = [
        .fullTime: "CF3CP", .partTime: "75GKK",
        .contract: "NJXCK", .internship: "VDTG7",
    ]
    static let remoteKey = "DSQF7"

    /// The country decides which national Indeed the API searches; the
    /// English locale makes Indeed label things in English.
    static func headers(country: Country) -> [String: String] {
        [
            "indeed-api-key": apiKey,
            "accept": "application/json",
            "indeed-locale": "en-\(country.code)",
            "user-agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 16_6_1 like Mac OS X) "
                + "AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 Indeed App 193.1",
            "indeed-app-info": "appv=193.1; appid=com.indeed.jobsearch; osv=16.6.1; os=ios; dtype=phone",
            "indeed-co": country.code,
        ]
    }

    /// Indeed allows one filter type per request: either a date window or a
    /// composite of keyword filters. English-only (Indeed's own per-job
    /// language tag) and job types go into the composite; a date window is
    /// then applied afterwards using the exact publish dates.
    func buildFilters(_ query: SearchQuery) -> String {
        var keywordFilters: [String] = []
        if query.englishOnly {
            keywordFilters.append(#"{ keyword: { field: "language", keys: ["en"] } }"#)
        }
        var keys = query.jobTypes.compactMap { Self.jobTypeKeys[$0] }
        if query.remote.contains(.remote) { keys.append(Self.remoteKey) }
        if !keys.isEmpty {
            let joined = keys.sorted().map { "\"\($0)\"" }.joined(separator: ", ")
            keywordFilters.append(#"{ keyword: { field: "attributes", keys: [\#(joined)] } }"#)
        }
        if !keywordFilters.isEmpty {
            return "filters: { composite: { filters: [\(keywordFilters.joined(separator: ", "))] } }"
        }
        if let days = query.datePosted.days {
            return #"filters: { date: { field: "dateOnIndeed", start: "\#(days * 24)h" } }"#
        }
        return ""
    }

    func buildQuery(_ query: SearchQuery, cursor: String?) -> String {
        let term = query.keywords.replacingOccurrences(of: "\"", with: "\\\"")
        let what = term.isEmpty ? "" : "what: \"\(term)\""
        let cur = cursor.map { "cursor: \"\($0)\"" } ?? ""
        // No location: the whole country (selected via the indeed-co header).
        return """
        query GetJobData {
            jobSearch(
                \(what)
                limit: 100
                \(cur)
                sort: DATE
                \(buildFilters(query))
            ) {
                pageInfo { nextCursor }
                results {
                    job {
                        key
                        title
                        language
                        datePublished
                        employer { name }
                        location { formatted { long } }
                        attributes { label }
                        compensation {
                            baseSalary { unitOfWork range { ... on Range { min max } } }
                            currencyCode
                        }
                        description { html }
                    }
                }
            }
        }
        """
    }

    struct GQLResponse: Decodable {
        struct DataBox: Decodable { let jobSearch: JobSearch? }
        struct JobSearch: Decodable {
            let pageInfo: PageInfo?
            let results: [Result]?
        }
        struct PageInfo: Decodable { let nextCursor: String? }
        struct Result: Decodable { let job: GQLJob? }
        struct GQLJob: Decodable {
            let key: String?
            let title: String?
            let language: String?
            let datePublished: Double?
            let employer: Employer?
            let location: Location?
            let attributes: [Attribute]?
            let compensation: Compensation?
            let description: Description?
        }
        struct Employer: Decodable { let name: String? }
        struct Location: Decodable { let formatted: Formatted? }
        struct Formatted: Decodable { let long: String? }
        struct Attribute: Decodable { let label: String? }
        struct Compensation: Decodable {
            let baseSalary: BaseSalary?
            let currencyCode: String?
        }
        struct BaseSalary: Decodable {
            let unitOfWork: String?
            let range: Range?
        }
        struct Range: Decodable {
            let min: Double?
            let max: Double?
        }
        struct Description: Decodable { let html: String? }
        let data: DataBox?
        let errors: [GQLError]?
    }
    struct GQLError: Decodable { let message: String? }

    func salaryText(_ comp: GQLResponse.Compensation?) -> String {
        guard let base = comp?.baseSalary, let range = base.range,
              range.min != nil || range.max != nil else { return "" }
        let cur = comp?.currencyCode ?? "EUR"
        let fmt: (Double) -> String = { v in
            v >= 1000 ? String(format: "%.0f", v) : String(format: "%.2f", v)
        }
        var parts: [String] = []
        if let min = range.min { parts.append(fmt(min)) }
        if let max = range.max, max != range.min { parts.append(fmt(max)) }
        let unit = (base.unitOfWork ?? "").lowercased()
        let suffix = unit.isEmpty ? "" : "/\(unit.replacingOccurrences(of: "_", with: " ").lowercased())"
        return parts.joined(separator: "–") + " " + cur + suffix
    }

    func toJob(_ g: GQLResponse.GQLJob, country: Country) -> Job? {
        guard let key = g.key, let title = g.title, !title.isEmpty else { return nil }
        var posted: Date?
        if let ms = g.datePublished {
            posted = Date(timeIntervalSince1970: ms / 1000)
        }
        var descText = ""
        if let html = g.description?.html {
            descText = HTMLText.plain(html)
        }
        let attrs = (g.attributes ?? []).compactMap(\.label)
        let knownTypes = ["Vollzeit", "Teilzeit", "Full-time", "Part-time", "Minijob", "Festanstellung", "Praktikum", "Werkstudent"]
        let types = attrs.filter { a in knownTypes.contains { a.localizedCaseInsensitiveContains($0) } }
        let isRemote = attrs.contains { $0.localizedCaseInsensitiveContains("Homeoffice") || $0.localizedCaseInsensitiveContains("Remote") }
        return Job(
            source: name,
            jobID: key,
            title: title,
            company: g.employer?.name ?? "",
            location: g.location?.formatted?.long ?? "",
            url: "https://\(country.indeedSubdomain).indeed.com/viewjob?jk=\(key)",
            postedDateRaw: posted.map { ISO8601DateFormatter().string(from: $0) } ?? "",
            posted: posted,
            remote: isRemote ? "Remote/Homeoffice" : "",
            salary: salaryText(g.compensation),
            employmentType: types.joined(separator: ", "),
            descriptionText: descText,
            languageHint: g.language
        )
    }

    public func search(_ query: SearchQuery) async throws -> [Job] {
        var jobs: [Job] = []
        var cursor: String?
        var pages = 0
        let filters = buildFilters(query)
        let postFilterDate = query.datePosted.cutoff != nil && !filters.contains("dateOnIndeed")
        let maxPages = min(max(query.limit / 50, 3), 15)
        while jobs.count < query.limit && pages < maxPages {
            let payload = try JSONSerialization.data(
                withJSONObject: ["query": buildQuery(query, cursor: cursor)])
            let data = try await HTTP.postJSON(
                Self.apiURL, body: payload, headers: Self.headers(country: query.country))
            let resp = try JSONDecoder().decode(GQLResponse.self, from: data)
            if let errs = resp.errors, !errs.isEmpty, resp.data?.jobSearch == nil {
                throw SourceError("Indeed API error: \(errs.first?.message ?? "unknown")")
            }
            let results = resp.data?.jobSearch?.results ?? []
            if results.isEmpty { break }
            var page = results.compactMap { $0.job.flatMap { toJob($0, country: query.country) } }
            if postFilterDate, let cutoff = query.datePosted.cutoff {
                page = page.filter { ($0.posted ?? .distantFuture) >= cutoff }
            }
            jobs.append(contentsOf: page)
            cursor = resp.data?.jobSearch?.pageInfo?.nextCursor
            if cursor == nil { break }
            pages += 1
        }
        return Array(jobs.prefix(query.limit))
    }
}
