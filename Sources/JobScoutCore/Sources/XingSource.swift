import Foundation
import SwiftSoup

/// Xing Jobs — parses the server-rendered public search results page
/// (no login required). Card structure verified 2026-07: each result is an
/// `<article data-testid="job-search-result">` whose visible text runs in a
/// stable order: title, company, location, [+ N weitere], employment type,
/// [salary…], "Job merken".
///
/// Since 2026-10 Xing redirects searches to its AI search, which ignores the
/// location parameter, so results are placed into the selected country
/// afterwards from their location text (Xing is DACH-only anyway).
public struct XingSource: JobSource {
    public let name = "xing"

    public init() {}

    static let base = "https://www.xing.com/jobs/search"

    static let employmentTypes: Set<String> = [
        "Vollzeit", "Teilzeit", "Freiberuflich", "Selbstständig", "Praktikum",
        "Werkstudent", "Ausbildung", "Trainee", "Befristet", "Festanstellung",
        "Full-time", "Part-time", "Internship", "Freelance", "Temporary",
    ]

    func sincePeriod(_ d: DatePosted) -> String? {
        switch d {
        case .any: return nil
        case .h24: return "LAST_24_HOURS"
        case .week: return "LAST_WEEK"
        case .month: return "LAST_MONTH"
        }
    }

    func params(_ query: SearchQuery, page: Int) -> [(String, String)] {
        var p: [(String, String)] = [("keywords", query.keywords)]
        if let sp = sincePeriod(query.datePosted) { p.append(("sincePeriod", sp)) }
        if page > 1 { p.append(("page", String(page))) }
        return p
    }

    func parse(_ html: String) throws -> [Job] {
        let doc = try SwiftSoup.parse(html)
        try doc.select("style, svg, script").remove()
        var jobs: [Job] = []
        for card in try doc.select("article[data-testid=job-search-result]").array() {
            guard let link = try card.select("a[href^=/jobs/]").first() else { continue }
            let href = try link.attr("href")
            let title = (try? link.attr("aria-label")) ?? ""
            let jobID = href.split(separator: "-").last.map(String.init) ?? href

            // Visible text pieces in DOM order.
            var texts: [String] = []
            for el in try card.select("*").array() {
                for node in el.textNodes() {
                    let t = node.text().trimmingCharacters(in: .whitespacesAndNewlines)
                    if t.count >= 2 { texts.append(t) }
                }
            }
            let badges = [
                "Job merken", "–", "Zu den Ersten gehören", "Be one of the first",
                "Schnelle Bewerbung", "Easy apply", "Neu", "New", "Top-Arbeitgeber",
                "Dringend gesucht", "Urgently hiring", "Urgently needed", "Top employer",
                "Letzte Chance", "Last chance",
            ]
            texts.removeAll { t in
                badges.contains(t) || t.hasPrefix("+ ") || t == title
            }
            // texts[0] is usually the title again; find company/location after it.
            var company = ""
            var location = ""
            var employment = ""
            var salaryParts: [String] = []
            var idx = 0
            if idx < texts.count { company = texts[idx]; idx += 1 }
            if idx < texts.count { location = texts[idx]; idx += 1 }
            for t in texts[min(idx, texts.count)...] {
                if Self.employmentTypes.contains(t) {
                    employment = t
                } else if t.contains("€") {
                    salaryParts.append(t)
                }
            }

            jobs.append(Job(
                source: name,
                jobID: jobID,
                title: title.isEmpty ? (texts.first ?? "") : title,
                company: company,
                location: location,
                url: "https://www.xing.com\(href)",
                salary: salaryParts.joined(separator: " – "),
                employmentType: employment
            ))
        }
        return jobs
    }

    public func search(_ query: SearchQuery) async throws -> [Job] {
        var jobs: [Job] = []
        var seen = Set<String>()
        var page = 1
        let maxPages = min(max(query.limit / 20 + 1, 5), 25)
        while jobs.count < query.limit && page <= maxPages {
            let url = HTTP.url(Self.base, params(query, page: page))
            let html = try await HTTP.getString(url, headers: [
                "Accept": "text/html,application/xhtml+xml",
            ])
            let cards = try parse(html)
            if cards.isEmpty { break }
            var added = 0
            for job in cards where seen.insert(job.jobID).inserted {
                added += 1
                guard Countries.place(job.location, in: query.country) != .elsewhere else { continue }
                jobs.append(job)
                if jobs.count >= query.limit { break }
            }
            if added == 0 { break }
            page += 1
            try? await Task.sleep(nanoseconds: UInt64(0.8 * 1_000_000_000))
        }
        return Array(jobs.prefix(query.limit))
    }
}
