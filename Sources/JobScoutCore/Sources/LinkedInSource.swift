import Foundation
import SwiftSoup

/// LinkedIn — public guest jobs endpoint (no login). Port of the proven
/// Python adapter from the job-platform project.
public struct LinkedInSource: JobSource {
    public let name = "linkedin"
    let delaySeconds: Double

    public init(delaySeconds: Double = 0.8) {
        self.delaySeconds = delaySeconds
    }

    static let searchURL = "https://www.linkedin.com/jobs-guest/jobs/api/seeMoreJobPostings/search"

    static let experienceCodes: [ExperienceLevel: [String]] = [
        .entry: ["1", "2"],       // internship, entry
        .mid: ["3", "4"],         // associate, mid-senior
        .senior: ["4", "5", "6"], // mid-senior, director, executive
    ]
    static let jobTypeCodes: [JobType: String] = [
        .fullTime: "F", .partTime: "P", .contract: "C",
        .temporary: "T", .internship: "I",
    ]
    static let remoteCodes: [RemoteType: String] = [
        .onSite: "1", .remote: "2", .hybrid: "3",
    ]
    static let dateCodes: [DatePosted: String] = [
        .h24: "r86400", .week: "r604800", .month: "r2592000",
    ]

    func params(_ query: SearchQuery, start: Int) -> [(String, String)] {
        var p: [(String, String)] = [
            ("keywords", query.keywords),
            ("start", String(start)),
            ("sortBy", "DD"),
        ]
        // A country name is a valid LinkedIn location and covers the whole country.
        p.append(("location", query.country.name))
        if let tpr = Self.dateCodes[query.datePosted] { p.append(("f_TPR", tpr)) }
        let exp = Set(query.experience.flatMap { Self.experienceCodes[$0] ?? [] })
        if !exp.isEmpty { p.append(("f_E", exp.sorted().joined(separator: ","))) }
        let jt = query.jobTypes.compactMap { Self.jobTypeCodes[$0] }
        if !jt.isEmpty { p.append(("f_JT", jt.sorted().joined(separator: ","))) }
        let wt = query.remote.compactMap { Self.remoteCodes[$0] }
        if !wt.isEmpty { p.append(("f_WT", wt.sorted().joined(separator: ","))) }
        return p
    }

    func parse(_ html: String) throws -> [Job] {
        let doc = try SwiftSoup.parse(html)
        var jobs: [Job] = []
        for li in try doc.select("li").array() {
            let card = try li.select("div.base-card").first() ?? li
            let title = try card.select(".base-search-card__title").first()?.text() ?? ""
            guard !title.isEmpty else { continue }

            let link = try card.select("a.base-card__full-link").first()
                ?? card.select("a[href]").first()
            let rawURL = (try? link?.attr("href")) ?? ""
            let url = rawURL.components(separatedBy: "?").first ?? ""

            let urn = (try? card.attr("data-entity-urn")) ?? ""
            var jobID = urn.contains(":")
                ? String(urn.split(separator: ":").last ?? "") : ""
            if jobID.isEmpty {
                jobID = url.components(separatedBy: CharacterSet.decimalDigits.inverted)
                    .first(where: { $0.count >= 6 }) ?? ""
            }

            let timeNode = try card.select("time").first()
            let postedRaw = (try? timeNode?.attr("datetime")) ?? ""
            let postedText = (try? timeNode?.text()) ?? ""
            let raw = postedRaw.isEmpty ? postedText : postedRaw

            jobs.append(Job(
                source: name,
                jobID: jobID,
                title: title,
                company: (try? card.select(".base-search-card__subtitle").first()?.text()) ?? "",
                location: (try? card.select(".job-search-card__location").first()?.text()) ?? "",
                url: url,
                postedDateRaw: raw,
                posted: DateParsing.parse(raw) ?? DateParsing.parseRelative(raw)
            ))
        }
        return jobs
    }

    public func search(_ query: SearchQuery) async throws -> [Job] {
        var jobs: [Job] = []
        var seen = Set<String>()
        var start = 0
        while jobs.count < query.limit {
            let url = HTTP.url(Self.searchURL, params(query, start: start))
            let html: String
            do {
                html = try await HTTP.getString(url, headers: [
                    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
                    "X-Requested-With": "XMLHttpRequest",
                ])
            } catch {
                if jobs.isEmpty { throw error }
                break // keep what we already have
            }
            let cards = try parse(html)
            if cards.isEmpty { break }
            var added = 0
            for job in cards {
                if !job.jobID.isEmpty {
                    guard seen.insert(job.jobID).inserted else { continue }
                }
                jobs.append(job)
                added += 1
                if jobs.count >= query.limit { break }
            }
            if added == 0 { break }
            start += cards.count
            try? await Task.sleep(nanoseconds: UInt64((delaySeconds + Double.random(in: 0...0.5)) * 1_000_000_000))
        }
        return Array(jobs.prefix(query.limit))
    }
}
