import Foundation
import SwiftSoup

/// StepStone.de — parses the server-rendered results page. Cards carry stable
/// `data-at` attributes (job-item, job-item-title, job-item-company-name,
/// job-item-location, job-item-timeago). Verified 2026-07.
///
/// StepStone sits behind bot protection; plain requests currently pass, but if
/// it blocks, the source reports an honest error rather than silently failing.
public struct StepStoneSource: JobSource {
    public let name = "stepstone"

    public init() {}

    /// StepStone route style: /jobs/{what}/in-{where}?radius=30
    func searchURL(_ query: SearchQuery, page: Int) -> URL {
        func slug(_ s: String) -> String {
            let map: [Character: String] = [
                "ä": "ae", "ö": "oe", "ü": "ue", "ß": "ss",
                "Ä": "ae", "Ö": "oe", "Ü": "ue",
            ]
            var out = ""
            for ch in s.lowercased() {
                if let m = map[ch] { out += m }
                else if ch.isLetter || ch.isNumber { out.append(ch) }
                else if ch == " " || ch == "-" { out.append("-") }
            }
            while out.contains("--") { out = out.replacingOccurrences(of: "--", with: "-") }
            return out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        }
        var path = "https://www.stepstone.de/jobs/\(slug(query.keywords.isEmpty ? "jobs" : query.keywords))"
        if !query.location.isEmpty { path += "/in-\(slug(query.location))" }
        var params: [(String, String)] = [("radius", String(query.radiusKm))]
        if page > 1 { params.append(("page", String(page))) }
        if query.datePosted != .any {
            params.append(("sort", "2")) // newest first, pairs with timeago post-filter
        }
        return HTTP.url(path, params)
    }

    func parse(_ html: String) throws -> [Job] {
        let doc = try SwiftSoup.parse(html)
        try doc.select("style, svg, script").remove()
        var jobs: [Job] = []
        for card in try doc.select("article[data-at=job-item]").array() {
            guard let titleLink = try card.select("a[data-at=job-item-title]").first() else { continue }
            let title = try titleLink.text().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            var href = try titleLink.attr("href")
            if href.hasPrefix("/") { href = "https://www.stepstone.de" + href }
            href = href.components(separatedBy: "?").first ?? href

            let jobID = href.components(separatedBy: CharacterSet.decimalDigits.inverted)
                .last(where: { $0.count >= 6 })
                ?? href

            let company = (try? card.select("[data-at=job-item-company-name]").first()?.text()) ?? ""
            let location = (try? card.select("[data-at=job-item-location]").first()?.text()) ?? ""
            let timeago = (try? card.select("[data-at=job-item-timeago]").first()?.text()) ?? ""
            let salary = (try? card.select("[data-at=job-item-salary-info]").first()?.text()) ?? ""
            let wfh = (try? card.select("[data-at=job-item-work-from-home]").first()?.text()) ?? ""

            jobs.append(Job(
                source: name,
                jobID: jobID,
                title: title,
                company: company ?? "",
                location: location ?? "",
                url: href,
                postedDateRaw: timeago ?? "",
                posted: DateParsing.parseRelative(timeago ?? ""),
                remote: wfh ?? "",
                salary: salary ?? ""
            ))
        }
        return jobs
    }

    public func search(_ query: SearchQuery) async throws -> [Job] {
        var jobs: [Job] = []
        var seen = Set<String>()
        var page = 1
        while jobs.count < query.limit && page <= 5 {
            let html: String
            do {
                html = try await HTTP.getString(searchURL(query, page: page), headers: [
                    "Accept": "text/html,application/xhtml+xml",
                ])
            } catch let e as HTTPError where e.status == 403 {
                throw SourceError("StepStone blocked this request (bot protection). Try again in a few minutes.")
            }
            let cards = try parse(html)
            if cards.isEmpty { break }
            var added = 0
            for job in cards where seen.insert(job.jobID).inserted {
                jobs.append(job)
                added += 1
                if jobs.count >= query.limit { break }
            }
            if added == 0 { break }
            page += 1
            try? await Task.sleep(nanoseconds: UInt64(1.0 * 1_000_000_000))
        }
        // StepStone has no reliable date URL param — post-filter via timeago.
        if let cutoff = query.datePosted.cutoff {
            jobs = jobs.filter { job in
                guard let posted = job.posted else { return true }
                return posted >= cutoff
            }
        }
        return Array(jobs.prefix(query.limit))
    }
}
