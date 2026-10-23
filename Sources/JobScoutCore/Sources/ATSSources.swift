import Foundation
import SwiftSoup

/// The applicant-tracking systems whose public feeds we can read for free.
public enum ATSKind: String, Codable, CaseIterable, Sendable {
    case personio, greenhouse, lever, recruitee, smartrecruiters

    public var label: String {
        switch self {
        case .personio: return "Personio"
        case .greenhouse: return "Greenhouse"
        case .lever: return "Lever"
        case .recruitee: return "Recruitee"
        case .smartrecruiters: return "SmartRecruiters"
        }
    }
}

/// A company on the user's watchlist, resolved to its ATS feed.
public struct ATSCompany: Codable, Identifiable, Hashable, Sendable {
    public var id: String { "\(ats.rawValue):\(slug)" }
    public var name: String
    public var ats: ATSKind
    /// Board token / account slug used in the feed URL.
    public var slug: String
    /// For Personio: full host (e.g. "acme.jobs.personio.de"); empty otherwise.
    public var host: String

    public init(name: String, ats: ATSKind, slug: String, host: String = "") {
        self.name = name
        self.ats = ats
        // Slugs and hosts go into feed URLs: keep them to the characters the
        // ATS vendors use, so a typed slug can't point a request elsewhere.
        self.slug = String(slug.unicodeScalars.filter {
            $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_")
        }.map(Character.init))
        self.host = Self.isPersonioHost(host) ? host.lowercased() : ""
    }

    static func isPersonioHost(_ host: String) -> Bool {
        host.lowercased().range(
            of: #"^[a-z0-9-]+\.jobs\.personio\.(de|com)$"#, options: .regularExpression) != nil
    }
}

/// Fetches all public postings of one ATS company, normalized to `Job`.
public enum ATSClient {
    public static func fetchJobs(for company: ATSCompany) async throws -> [Job] {
        switch company.ats {
        case .personio: return try await personio(company)
        case .greenhouse: return try await greenhouse(company)
        case .lever: return try await lever(company)
        case .recruitee: return try await recruitee(company)
        case .smartrecruiters: return try await smartrecruiters(company)
        }
    }

    // MARK: Personio — https://{slug}.jobs.personio.de/xml

    static func personio(_ c: ATSCompany) async throws -> [Job] {
        let host = ATSCompany.isPersonioHost(c.host) ? c.host : "\(c.slug).jobs.personio.de"
        let xml = try await HTTP.getString(try HTTP.makeURL("https://\(host)/xml"))
        let doc = try SwiftSoup.parse(xml, "", Parser.xmlParser())
        var jobs: [Job] = []
        for pos in try doc.select("position").array() {
            let id = (try? pos.select("id").first()?.text()) ?? ""
            let title = (try? pos.select("name").first()?.text()) ?? ""
            guard !title.isEmpty else { continue }
            let offices = pos.children().array()
                .filter { $0.tagName() == "office" }
                .compactMap { try? $0.text() }
            let created = (try? pos.select("createdAt").first()?.text()) ?? ""
            let sections = (try? pos.select("jobDescription").array()) ?? []
            let description = sections.compactMap { section -> String? in
                let heading = (try? section.select("name").first()?.text()) ?? ""
                let body = HTMLText.plain((try? section.select("value").first()?.text()) ?? "")
                guard !body.isEmpty else { return nil }
                return heading.isEmpty ? body : "\(heading)\n\(body)"
            }.joined(separator: "\n\n")
            jobs.append(Job(
                source: "career-site",
                jobID: "personio-\(c.slug)-\(id.isEmpty ? title : id)",
                title: title,
                company: c.name,
                location: offices.joined(separator: ", "),
                url: "https://\(host)/job/\(id)",
                postedDateRaw: created,
                posted: DateParsing.parse(created),
                employmentType: (try? pos.select("schedule").first()?.text()) ?? "",
                descriptionText: description
            ))
        }
        return jobs
    }

    // MARK: Greenhouse — https://boards-api.greenhouse.io/v1/boards/{slug}/jobs

    struct GHResponse: Decodable {
        struct GHJob: Decodable {
            let id: Int?
            let title: String?
            let absolute_url: String?
            let updated_at: String?
            let location: GHLocation?
            let content: String?
        }
        struct GHLocation: Decodable { let name: String? }
        let jobs: [GHJob]?
    }

    static func greenhouse(_ c: ATSCompany) async throws -> [Job] {
        let url = try HTTP.makeURL("https://boards-api.greenhouse.io/v1/boards/\(c.slug)/jobs?content=true")
        let data = try await HTTP.get(url)
        let resp = try JSONDecoder().decode(GHResponse.self, from: data)
        return (resp.jobs ?? []).compactMap { j in
            guard let title = j.title else { return nil }
            return Job(
                source: "career-site",
                jobID: "greenhouse-\(c.slug)-\(j.id ?? 0)",
                title: title,
                company: c.name,
                location: j.location?.name ?? "",
                url: j.absolute_url ?? "",
                postedDateRaw: j.updated_at ?? "",
                posted: DateParsing.parse(j.updated_at ?? ""),
                descriptionText: HTMLText.plain(j.content ?? "")
            )
        }
    }

    // MARK: Lever — https://api.lever.co/v0/postings/{slug}?mode=json

    struct LeverJob: Decodable {
        let id: String?
        let text: String?
        let hostedUrl: String?
        let createdAt: Double?
        let categories: LeverCategories?
        let descriptionPlain: String?
        let lists: [LeverList]?
        let additionalPlain: String?
    }
    struct LeverList: Decodable {
        let text: String?
        let content: String?
    }
    struct LeverCategories: Decodable {
        let location: String?
        let commitment: String?
    }

    static func lever(_ c: ATSCompany) async throws -> [Job] {
        let url = try HTTP.makeURL("https://api.lever.co/v0/postings/\(c.slug)?mode=json")
        let data = try await HTTP.get(url)
        let list = try JSONDecoder().decode([LeverJob].self, from: data)
        return list.compactMap { j in
            guard let title = j.text else { return nil }
            let posted = j.createdAt.map { Date(timeIntervalSince1970: $0 / 1000) }
            let lists = (j.lists ?? []).map { list in
                [list.text ?? "", HTMLText.plain(list.content ?? "")]
                    .filter { !$0.isEmpty }.joined(separator: "\n")
            }
            let description = ([j.descriptionPlain ?? ""] + lists + [j.additionalPlain ?? ""])
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }.joined(separator: "\n\n")
            return Job(
                source: "career-site",
                jobID: "lever-\(c.slug)-\(j.id ?? title)",
                title: title,
                company: c.name,
                location: j.categories?.location ?? "",
                url: j.hostedUrl ?? "",
                postedDateRaw: "",
                posted: posted,
                employmentType: j.categories?.commitment ?? "",
                descriptionText: description
            )
        }
    }

    // MARK: Recruitee — https://{slug}.recruitee.com/api/offers/

    struct RecruiteeResponse: Decodable {
        struct Offer: Decodable {
            let id: Int?
            let title: String?
            let slug: String?
            let location: String?
            let careers_url: String?
            let created_at: String?
            let employment_type_code: String?
            let description: String?
            let requirements: String?
        }
        let offers: [Offer]?
    }

    static func recruitee(_ c: ATSCompany) async throws -> [Job] {
        let url = try HTTP.makeURL("https://\(c.slug).recruitee.com/api/offers/")
        let data = try await HTTP.get(url)
        let resp = try JSONDecoder().decode(RecruiteeResponse.self, from: data)
        return (resp.offers ?? []).compactMap { o in
            guard let title = o.title else { return nil }
            return Job(
                source: "career-site",
                jobID: "recruitee-\(c.slug)-\(o.id ?? 0)",
                title: title,
                company: c.name,
                location: o.location ?? "",
                url: o.careers_url ?? "https://\(c.slug).recruitee.com/o/\(o.slug ?? "")",
                postedDateRaw: o.created_at ?? "",
                posted: DateParsing.parse(o.created_at ?? ""),
                employmentType: o.employment_type_code ?? "",
                descriptionText: [o.description, o.requirements]
                    .map { HTMLText.plain($0 ?? "") }
                    .filter { !$0.isEmpty }.joined(separator: "\n\n")
            )
        }
    }

    // MARK: SmartRecruiters — https://api.smartrecruiters.com/v1/companies/{slug}/postings

    struct SRResponse: Decodable {
        struct Posting: Decodable {
            let id: String?
            let name: String?
            let releasedDate: String?
            let location: SRLocation?
        }
        struct SRLocation: Decodable {
            let city: String?
            let country: String?
        }
        let content: [Posting]?
    }

    static func smartrecruiters(_ c: ATSCompany) async throws -> [Job] {
        var jobs: [Job] = []
        var offset = 0
        while offset <= 400 {
            let url = try HTTP.makeURL("https://api.smartrecruiters.com/v1/companies/\(c.slug)/postings?limit=100&offset=\(offset)")
            let data = try await HTTP.get(url)
            let resp = try JSONDecoder().decode(SRResponse.self, from: data)
            let posts = resp.content ?? []
            if posts.isEmpty { break }
            jobs += posts.compactMap { p in
                guard let title = p.name, let id = p.id else { return nil }
                let loc = [p.location?.city, p.location?.country?.uppercased()]
                    .compactMap { $0 }.joined(separator: ", ")
                return Job(
                    source: "career-site",
                    jobID: "smartrecruiters-\(c.slug)-\(id)",
                    title: title,
                    company: c.name,
                    location: loc,
                    url: "https://jobs.smartrecruiters.com/\(c.slug)/\(id)",
                    postedDateRaw: p.releasedDate ?? "",
                    posted: DateParsing.parse(p.releasedDate ?? "")
                )
            }
            if posts.count < 100 { break }
            offset += 100
        }
        return jobs
    }
}

/// Tries every ATS pattern for a company name/slug until one answers with
/// real postings data. Returns the resolved company or nil.
public enum ATSDetector {
    public static func slugCandidates(for input: String) -> [String] {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var candidates: [String] = []
        let compact = trimmed.components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
        let hyphen = trimmed
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: "-")
        let firstWord = trimmed.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .first(where: { !$0.isEmpty }) ?? trimmed
        for c in [trimmed.replacingOccurrences(of: " ", with: ""), compact, hyphen, firstWord]
        where !c.isEmpty && !candidates.contains(c) {
            candidates.append(c)
        }
        return candidates
    }

    /// If the user pasted a careers URL, resolve the ATS directly from it.
    public static func fromURL(_ input: String) -> ATSCompany? {
        guard input.contains("http") || input.contains(".") else { return nil }
        let lower = input.lowercased()
        func extract(_ pattern: String) -> String? {
            guard let r = try? NSRegularExpression(pattern: pattern),
                  let m = r.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
                  m.numberOfRanges > 1,
                  let range = Range(m.range(at: 1), in: lower)
            else { return nil }
            return String(lower[range])
        }
        if let slug = extract(#"([a-z0-9-]+)\.jobs\.personio\.(?:de|com)"#) {
            let host = lower.contains("personio.com") ? "\(slug).jobs.personio.com" : "\(slug).jobs.personio.de"
            return ATSCompany(name: slug.capitalized, ats: .personio, slug: slug, host: host)
        }
        if let slug = extract(#"greenhouse\.io/(?:boards/)?(?:v1/boards/)?([a-z0-9-]+)"#) {
            return ATSCompany(name: slug.capitalized, ats: .greenhouse, slug: slug)
        }
        if let slug = extract(#"(?:jobs|api)\.lever\.co/(?:v0/postings/)?([a-z0-9-]+)"#) {
            return ATSCompany(name: slug.capitalized, ats: .lever, slug: slug)
        }
        if let slug = extract(#"([a-z0-9-]+)\.recruitee\.com"#) {
            return ATSCompany(name: slug.capitalized, ats: .recruitee, slug: slug)
        }
        if let slug = extract(#"(?:jobs|careers)\.smartrecruiters\.com/([a-zA-Z0-9-]+)"#) {
            return ATSCompany(name: slug, ats: .smartrecruiters, slug: slug)
        }
        return nil
    }

    public static func detect(companyNameOrURL input: String) async -> ATSCompany? {
        if let direct = fromURL(input) {
            // Verify the direct hit actually serves data.
            if let verified = await verify(direct) { return verified }
            return direct
        }
        let name = input.trimmingCharacters(in: .whitespacesAndNewlines)
        for slug in slugCandidates(for: name) {
            for kind in ATSKind.allCases {
                var candidate = ATSCompany(name: name, ats: kind, slug: slug)
                if kind == .personio { candidate.host = "\(slug).jobs.personio.de" }
                if let verified = await verify(candidate) { return verified }
                // Personio also runs on .com hosts.
                if kind == .personio {
                    candidate.host = "\(slug).jobs.personio.com"
                    if let verified = await verify(candidate) { return verified }
                }
            }
        }
        return nil
    }

    static func verify(_ c: ATSCompany) async -> ATSCompany? {
        do {
            let jobs = try await ATSClient.fetchJobs(for: c)
            return jobs.isEmpty ? nil : c
        } catch {
            return nil
        }
    }
}

/// A JobSource that fans out over the user's company watchlist.
public struct CompanyWatchlistSource: JobSource {
    public let name = "career-site"
    let companies: [ATSCompany]

    public init(companies: [ATSCompany]) {
        self.companies = companies
    }

    /// Every open position of every watched company, in any country.
    public func allJobs() async -> [Job] {
        await withTaskGroup(of: [Job].self) { group in
            for company in companies {
                group.addTask {
                    (try? await ATSClient.fetchJobs(for: company)) ?? []
                }
            }
            var out: [Job] = []
            for await jobs in group { out += jobs }
            return out
        }
    }

    public func search(_ query: SearchQuery) async throws -> [Job] {
        guard !companies.isEmpty else { return [] }
        let keywordTokens = query.keywords.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }

        var filtered = await allJobs().filter {
            Countries.place($0.location, in: query.country) != .elsewhere
        }
        if !keywordTokens.isEmpty {
            filtered = filtered.filter { job in
                let t = job.title.lowercased()
                return keywordTokens.contains { t.contains($0) }
            }
        }
        if let cutoff = query.datePosted.cutoff {
            filtered = filtered.filter { job in
                guard let posted = job.posted else { return true }
                return posted >= cutoff
            }
        }
        return Array(filtered.prefix(query.limit))
    }
}
