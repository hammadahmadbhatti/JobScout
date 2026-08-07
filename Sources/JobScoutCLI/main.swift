import Foundation
import JobScoutCore

// Minimal CLI for testing the engine headlessly:
//   jobscout-cli search --keywords Koch --location Berlin \
//       --sources linkedin,arbeitsagentur,indeed,xing,stepstone \
//       --date week --limit 10 --lang de --types part-time --json
//   jobscout-cli detect-ats "Zalando"
//   jobscout-cli company-jobs --ats greenhouse --slug gitlab

func arg(_ name: String) -> String? {
    let args = CommandLine.arguments
    guard let i = args.firstIndex(of: "--\(name)"), i + 1 < args.count else { return nil }
    return args[i + 1]
}
func flag(_ name: String) -> Bool { CommandLine.arguments.contains("--\(name)") }

func printJobs(_ jobs: [Job], json: Bool) {
    if json {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(jobs) {
            print(String(decoding: data, as: UTF8.self))
        }
        return
    }
    let df = DateFormatter()
    df.dateFormat = "yyyy-MM-dd"
    for (i, j) in jobs.enumerated() {
        let date = j.posted.map { df.string(from: $0) } ?? (j.postedDateRaw.isEmpty ? "—" : j.postedDateRaw)
        var line = "\(i + 1). [\(j.source)] \(j.title) — \(j.company)"
        if !j.location.isEmpty { line += " (\(j.location))" }
        line += " [\(date)]"
        if !j.salary.isEmpty { line += " 💰 \(j.salary)" }
        if !j.employmentType.isEmpty { line += " · \(j.employmentType)" }
        print(line)
        print("   \(j.url)")
    }
}

let mode = CommandLine.arguments.dropFirst().first ?? "search"

switch mode {
case "detect-ats":
    let name = CommandLine.arguments.dropFirst(2).first ?? ""
    guard !name.isEmpty else {
        print("usage: jobscout-cli detect-ats <company name or careers URL>")
        exit(1)
    }
    let sem = DispatchSemaphore(value: 0)
    Task {
        if let company = await ATSDetector.detect(companyNameOrURL: name) {
            print("✅ \(company.name): \(company.ats.label) (slug: \(company.slug)\(company.host.isEmpty ? "" : ", host: \(company.host)"))")
            let jobs = (try? await ATSClient.fetchJobs(for: company)) ?? []
            print("   \(jobs.count) open positions")
            for j in jobs.prefix(5) { print("   – \(j.title) (\(j.location))") }
        } else {
            print("❌ No supported ATS found for '\(name)' (tried Personio, Greenhouse, Lever, Recruitee, SmartRecruiters)")
        }
        sem.signal()
    }
    sem.wait()

case "company-jobs":
    guard let atsRaw = arg("ats"), let kind = ATSKind(rawValue: atsRaw), let slug = arg("slug") else {
        print("usage: jobscout-cli company-jobs --ats <personio|greenhouse|lever|recruitee|smartrecruiters> --slug <slug>")
        exit(1)
    }
    let company = ATSCompany(name: slug, ats: kind, slug: slug)
    let sem = DispatchSemaphore(value: 0)
    Task {
        do {
            let jobs = try await ATSClient.fetchJobs(for: company)
            printJobs(jobs, json: flag("json"))
            print("— \(jobs.count) jobs")
        } catch {
            print("error: \(error)")
        }
        sem.signal()
    }
    sem.wait()

default: // search
    var query = SearchQuery()
    query.keywords = arg("keywords") ?? ""
    query.location = arg("location") ?? ""
    query.limit = Int(arg("limit") ?? "15") ?? 15
    query.radiusKm = Int(arg("radius") ?? "25") ?? 25
    if let d = arg("date") {
        query.datePosted = DatePosted(rawValue: d) ?? .any
    }
    if let langs = arg("lang") {
        query.languages = Set(langs.split(separator: ",").map(String.init))
    }
    if let types = arg("types") {
        query.jobTypes = Set(types.split(separator: ",").compactMap { JobType(rawValue: String($0)) })
    }
    if let exp = arg("experience") {
        query.experience = Set(exp.split(separator: ",").compactMap { ExperienceLevel(rawValue: String($0)) })
    }
    let sourceNames = (arg("sources") ?? "arbeitsagentur").split(separator: ",").map(String.init)
    let sources = SourceRegistry.make(names: sourceNames)
    guard !sources.isEmpty else {
        print("no valid sources; choose from: \(SourceRegistry.platformNames.joined(separator: ", "))")
        exit(1)
    }

    let sem = DispatchSemaphore(value: 0)
    let q = query
    Task {
        let result = await Aggregator.run(queries: [q], sources: sources)
        for s in result.statuses {
            if let e = s.error {
                print("⚠️  \(s.source): \(e)")
            } else {
                print("✓ \(s.source): \(s.count) jobs")
            }
        }
        print("")
        printJobs(result.jobs, json: flag("json"))
        print("— \(result.jobs.count) after merge/filters")
        sem.signal()
    }
    sem.wait()
}
