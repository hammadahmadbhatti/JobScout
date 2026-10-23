import Foundation
import JobScoutCore

// Minimal CLI for testing the engine headlessly:
//   jobscout-cli search --keywords "data analyst" --country DE \
//       --sources linkedin,arbeitsagentur,indeed,xing,stepstone \
//       --date week --limit 10 --types full-time [--any-language] \
//       [--details 5] [--json]
//   jobscout-cli countries
//   jobscout-cli export-applications [--out path.xlsx]
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
case "countries":
    for c in Countries.all {
        let boards = SourceRegistry.platformNames.filter { SourceRegistry.isAvailable($0, in: c) }
        print("\(c.code)  \(c.label.padding(toLength: 26, withPad: " ", startingAt: 0)) \(boards.joined(separator: ", "))")
    }

case "export-applications":
    // Rebuilds the Excel sheet from the app's saved applications.
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let input = URL(fileURLWithPath: arg("in")
        ?? support.appendingPathComponent("JobScout/applications.json").path)
    let output = URL(fileURLWithPath: arg("out") ?? "Job Applications.xlsx")
    do {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let apps = try dec.decode([TrackedApplication].self, from: Data(contentsOf: input))
        try ApplicationsWorkbook.build(apps).write(to: output, options: .atomic)
        print("✅ \(apps.count) applications → \(output.path)")
    } catch {
        print("error: \(error)")
        exit(1)
    }

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
    if let c = arg("country") {
        guard let country = Countries.find(c) else {
            print("unknown country '\(c)' — run `jobscout-cli countries`")
            exit(1)
        }
        query.country = country
    }
    query.limit = Int(arg("limit") ?? "15") ?? 15
    query.englishOnly = !flag("any-language")
    if let d = arg("date") {
        query.datePosted = DatePosted(rawValue: d) ?? .any
    }
    if let types = arg("types") {
        query.jobTypes = Set(types.split(separator: ",").compactMap { JobType(rawValue: String($0)) })
    }
    if let exp = arg("experience") {
        query.experience = Set(exp.split(separator: ",").compactMap { ExperienceLevel(rawValue: String($0)) })
    }
    let sourceNames = (arg("sources") ?? "linkedin,indeed").split(separator: ",").map(String.init)
        .filter { name in
            let ok = SourceRegistry.isAvailable(name, in: query.country)
            if !ok { print("–  \(name): \(SourceRegistry.availabilityNote(name) ?? "not available") — skipped") }
            return ok
        }
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
        print("— \(result.jobs.count) after merge/filters (\(result.hiddenNonEnglish) non-English postings hidden)")

        // --details N: fetch full descriptions and check language + German requirement.
        let detailCount = Int(arg("details") ?? "0") ?? 0
        if detailCount > 0 {
            print("\nFull descriptions:")
            for job in result.jobs.prefix(detailCount) {
                do {
                    let text = try await JobDetails.description(for: job)
                    let verdict = LanguageDetector.verdict(for: job, description: text)
                    let (req, snippet) = GermanRequirement.detect(in: text)
                    print("✓ [\(job.source)] \(job.title) — \(text.count) chars, \(verdict.rawValue), \(req.label)\(snippet.map { " «\($0)»" } ?? "")")
                    print("   " + text.prefix(160).replacingOccurrences(of: "\n", with: " ⏎ "))
                } catch {
                    let msg = (error as? HTTPError)?.description ?? (error as? SourceError)?.message ?? "\(error)"
                    print("✗ [\(job.source)] \(job.title) — \(msg)")
                }
            }
        }
        sem.signal()
    }
    sem.wait()
}
