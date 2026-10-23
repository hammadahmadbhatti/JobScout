import Foundation
import SwiftSoup

/// Turns posting HTML into readable plain text: paragraphs and line breaks
/// survive, list items become "• " bullets, whitespace is tidied.
public enum HTMLText {
    private static let blockTags: Set<String> = [
        "p", "div", "section", "article", "header", "footer", "ul", "ol", "li",
        "h1", "h2", "h3", "h4", "h5", "h6", "tr", "table", "blockquote", "dd", "dt",
    ]

    public static func plain(_ html: String) -> String {
        var source = html
        // Some feeds (Greenhouse, JSON-LD) ship the HTML entity-escaped.
        if !source.contains("<"), source.contains("&lt;"),
           let unescaped = try? Entities.unescape(source) {
            source = unescaped
        }
        guard let doc = try? SwiftSoup.parseBodyFragment(source),
              let body = doc.body() else { return tidy(source) }
        var out = ""
        walk(body, into: &out)
        return tidy(out)
    }

    private static func walk(_ node: Node, into out: inout String) {
        if let text = node as? TextNode {
            out += text.text()
            return
        }
        guard let el = node as? Element else { return }
        let tag = el.tagName().lowercased()
        if tag == "script" || tag == "style" { return }
        if tag == "br" { out += "\n"; return }
        let isBlock = blockTags.contains(tag)
        if isBlock { out += "\n" }
        if tag == "li" { out += "• " }
        for child in el.getChildNodes() { walk(child, into: &out) }
        if isBlock { out += "\n" }
    }

    static func tidy(_ s: String) -> String {
        let lines = s.replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{00AD}", with: "") // soft hyphens
            .components(separatedBy: .newlines)
            .map { line in
                line.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
            }
        var result: [String] = []
        for line in lines {
            if line.isEmpty, result.last?.isEmpty ?? true { continue }
            result.append(line)
        }
        while result.last?.isEmpty == true { result.removeLast() }
        return result.joined(separator: "\n")
    }
}

/// Fetches the complete description of a posting — shown in the detail pane,
/// used to verify the posting language, and saved with every application.
public enum JobDetails {
    public static func description(for job: Job) async throws -> String {
        let text: String
        switch job.source {
        case "linkedin": text = try await linkedIn(job)
        case "indeed": text = try await indeed(job)
        case "arbeitsagentur": text = try await arbeitsagentur(job)
        case "career-site": text = try await careerSite(job)
        default: text = try await fromPage(job.url) // Xing, StepStone
        }
        let clean = text
            .replacingOccurrences(of: #"^(null\s*)+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw SourceError("The posting has no description text.") }
        if looksLikeCookieNotice(clean) {
            throw SourceError("The posting only contains a cookie notice — open it in the browser.")
        }
        return clean
    }

    /// Some employers' feeds deliver their cookie banner instead of the ad.
    static func looksLikeCookieNotice(_ text: String) -> Bool {
        guard text.count < 4000 else { return false }
        let head = text.prefix(400).lowercased()
        return ["einwilligung", "cookie", "consent", "datenschutzerklärung"]
            .filter { head.contains($0) }.count >= 1
            && ["personenbezogene daten", "personal data", "ip-adressen", "ip address",
                "tracking", "datenschutz", "privacy"]
            .contains { text.lowercased().contains($0) }
    }

    // MARK: LinkedIn — guest job-posting endpoint (same family as search)

    static func linkedIn(_ job: Job) async throws -> String {
        guard !job.jobID.isEmpty else { return try await fromPage(job.url) }
        let url = try HTTP.makeURL("https://www.linkedin.com/jobs-guest/jobs/api/jobPosting/\(job.jobID)")
        let html = try await HTTP.getString(url, headers: [
            "Accept": "text/html,application/xhtml+xml",
        ])
        let doc = try SwiftSoup.parse(html)
        guard let markup = try doc.select(".show-more-less-html__markup").first()
            ?? doc.select(".description__text").first()
        else { throw SourceError("LinkedIn returned no description for this job.") }
        return plainText(of: markup)
    }

    // MARK: Indeed — description arrives with search; jobData as fallback

    static func indeed(_ job: Job) async throws -> String {
        if !job.descriptionText.isEmpty { return job.descriptionText }
        let key = job.jobID.filter { $0.isLetter || $0.isNumber }
        let query = """
        query { jobData(jobKeys: ["\(key)"]) { results { job { description { html } } } } }
        """
        let body = try JSONSerialization.data(withJSONObject: ["query": query])
        let country = Countries.all.first {
            job.url.hasPrefix("https://\($0.indeedSubdomain).indeed.com")
        } ?? .germany
        let data = try await HTTP.postJSON(
            IndeedSource.apiURL, body: body, headers: IndeedSource.headers(country: country))
        struct Response: Decodable {
            struct DataBox: Decodable { let jobData: JobData? }
            struct JobData: Decodable { let results: [Result]? }
            struct Result: Decodable { let job: J? }
            struct J: Decodable { let description: D? }
            struct D: Decodable { let html: String? }
            let data: DataBox?
        }
        let html = try JSONDecoder().decode(Response.self, from: data)
            .data?.jobData?.results?.first?.job?.description?.html ?? ""
        return HTMLText.plain(html)
    }

    // MARK: Arbeitsagentur — official job-details endpoint (refnr base64)

    static func arbeitsagentur(_ job: Job) async throws -> String {
        let encoded = Data(job.jobID.utf8).base64EncodedString()
        let url = try HTTP.makeURL("https://rest.arbeitsagentur.de/jobboerse/jobsuche-service/pc/v4/jobdetails/\(encoded)")
        struct Detail: Decodable { let stellenangebotsBeschreibung: String? }
        do {
            let data = try await HTTP.get(url, headers: ["X-API-Key": ArbeitsagenturSource.apiKey])
            let text = try JSONDecoder().decode(Detail.self, from: data).stellenangebotsBeschreibung ?? ""
            if !text.isEmpty { return HTMLText.plain(text) }
        } catch let e as HTTPError where e.status == 404 {
            // Postings with an external link are sometimes only described there.
        }
        if !job.url.contains("arbeitsagentur.de") { return try await fromPage(job.url) }
        throw SourceError("Arbeitsagentur has no description for this posting.")
    }

    // MARK: Company career sites

    static func careerSite(_ job: Job) async throws -> String {
        if !job.descriptionText.isEmpty { return job.descriptionText }
        if let url = URL(string: job.url), url.host == "jobs.smartrecruiters.com" {
            let parts = url.pathComponents.filter { $0 != "/" }
            if parts.count >= 2 {
                return try await smartRecruiters(company: parts[0], id: parts[1])
            }
        }
        return try await fromPage(job.url)
    }

    static func smartRecruiters(company: String, id: String) async throws -> String {
        let url = try HTTP.makeURL("https://api.smartrecruiters.com/v1/companies/\(company)/postings/\(id)")
        struct Posting: Decodable {
            struct JobAd: Decodable { let sections: [String: Section]? }
            struct Section: Decodable { let title: String?; let text: String? }
            let jobAd: JobAd?
        }
        let posting = try JSONDecoder().decode(Posting.self, from: try await HTTP.get(url))
        let order = ["companyDescription", "jobDescription", "qualifications", "additionalInformation"]
        let sections = posting.jobAd?.sections ?? [:]
        return order.compactMap { key -> String? in
            guard let s = sections[key], let text = s.text, !text.isEmpty else { return nil }
            let heading = (s.title ?? "").isEmpty ? "" : "\(s.title!)\n"
            return heading + HTMLText.plain(text)
        }.joined(separator: "\n\n")
    }

    // MARK: Any job page — schema.org JobPosting, else the main content

    public static func fromPage(_ urlString: String) async throws -> String {
        guard let url = URL(string: urlString), HTTP.isWebURL(url) else {
            throw SourceError("Invalid job link.")
        }
        let html = try await HTTP.getString(url, headers: [
            "Accept": "text/html,application/xhtml+xml",
        ])
        let doc = try SwiftSoup.parse(html)
        for script in try doc.select("script[type=application/ld+json]").array() {
            let raw = script.data()
            guard let data = raw.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data),
                  let posting = findJobPosting(json),
                  let desc = posting["description"] as? String, !desc.isEmpty
            else { continue }
            return HTMLText.plain(desc)
        }
        try doc.select("script, style, nav, header, footer, noscript, svg, form").remove()
        if let main = try doc.select("main, article, [role=main]").first() {
            let text = plainText(of: main)
            if text.count > 300 { return text }
        }
        throw SourceError("Couldn't find the description on the job page — open it in the browser.")
    }

    static func findJobPosting(_ json: Any) -> [String: Any]? {
        if let list = json as? [Any] {
            for item in list { if let p = findJobPosting(item) { return p } }
            return nil
        }
        guard let obj = json as? [String: Any] else { return nil }
        let type = obj["@type"]
        if (type as? String) == "JobPosting" || ((type as? [String])?.contains("JobPosting") ?? false) {
            return obj
        }
        if let graph = obj["@graph"] { return findJobPosting(graph) }
        return nil
    }

    static func plainText(of element: Element) -> String {
        HTMLText.plain((try? element.html()) ?? "")
    }
}
