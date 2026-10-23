import Foundation
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import JobScoutCore

/// Simple JSON file persistence in ~/Library/Application Support/JobScout.
enum Store {
    static let dir: URL = {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("JobScout", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static func load<T: Decodable>(_ name: String) -> T? {
        let url = dir.appendingPathComponent(name)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(T.self, from: data)
    }

    static func save<T: Encodable>(_ value: T, as name: String) {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(value) else { return }
        try? data.write(to: dir.appendingPathComponent(name), options: .atomic)
    }
}

enum SidebarItem: String, CaseIterable, Identifiable {
    case search, applications, companies, saved
    var id: String { rawValue }

    var label: String {
        switch self {
        case .search: return "Search"
        case .applications: return "Applications"
        case .companies: return "Companies"
        case .saved: return "Saved jobs"
        }
    }

    var icon: String {
        switch self {
        case .search: return "magnifyingglass"
        case .applications: return "checklist"
        case .companies: return "building.2"
        case .saved: return "star"
        }
    }
}

/// Progress of the background check that reads full descriptions to confirm
/// which postings are really in English.
struct LanguageCheck {
    var total = 0
    var done = 0
    /// Sources that started refusing requests; their jobs stay unverified.
    var stoppedSources: Set<String> = []
    var isRunning: Bool { done < total }
}

enum ExcelStatus: Equatable {
    case idle
    case saved(Date)
    case failed(String)
}

private enum Keys {
    static let country = "search.country"
    static let englishOnly = "search.englishOnly"
    static let hideApplied = "search.hideApplied"
    static let limit = "search.limitPerSource"
    static let verify = "search.verifyLanguage"
    static let excelPath = "tracker.excelPath"
}

@MainActor
final class AppState: ObservableObject {
    private let defaults = UserDefaults.standard

    // MARK: Search form
    @Published var keywords = ""
    @Published var countryCode: String {
        didSet { defaults.set(countryCode, forKey: Keys.country) }
    }
    @Published var datePosted: DatePosted = .any
    @Published var jobTypes: Set<JobType> = []
    @Published var experience: Set<ExperienceLevel> = []
    @Published var remote: Set<RemoteType> = []
    /// Only English-language postings (on by default — the app's focus).
    @Published var englishOnly: Bool {
        didSet {
            defaults.set(englishOnly, forKey: Keys.englishOnly)
            // Indeed filters natively and German titles are dropped up front,
            // so switching needs fresh results.
            if hasSearched, oldValue != englishOnly { runSearch() }
        }
    }
    @Published var hideApplied: Bool {
        didSet { defaults.set(hideApplied, forKey: Keys.hideApplied) }
    }
    @Published var limitPerSource: Int {
        didSet { defaults.set(limitPerSource, forKey: Keys.limit) }
    }
    /// Read full descriptions in the background to confirm English postings.
    @Published var verifyLanguage: Bool {
        didSet { defaults.set(verifyLanguage, forKey: Keys.verify) }
    }

    var country: Country { Countries.byCode[countryCode] ?? .germany }

    // MARK: Results
    @Published var results: [Job] = []
    @Published var statuses: [SourceStatus] = []
    @Published var isSearching = false
    @Published var hasSearched = false
    @Published var selection: Set<String> = []
    /// Non-English postings the search dropped by title (English-only mode).
    @Published private(set) var hiddenByTitle = 0

    // MARK: Descriptions & language (keyed by Job.id)
    @Published private(set) var descriptions: [String: String] = [:]
    @Published private(set) var descriptionErrors: [String: String] = [:]
    @Published private(set) var loadingDescriptions: Set<String> = []
    @Published private(set) var verdicts: [String: LanguageDetector.Verdict] = [:]
    @Published private(set) var germanRequirements: [String: GermanRequirement] = [:]
    @Published private(set) var languageCheck = LanguageCheck()
    private var checkTask: Task<Void, Never>?

    // MARK: Persisted data
    @Published var enabledSources: Set<String> {
        didSet { Store.save(Array(enabledSources), as: "sources.json") }
    }
    @Published var watchlist: [ATSCompany] {
        didSet { Store.save(watchlist, as: "watchlist.json") }
    }
    @Published var favorites: [Job] {
        didSet { Store.save(favorites, as: "favorites.json") }
    }

    // MARK: Applications
    /// The source of truth for the tracker; the Excel file mirrors it.
    @Published private(set) var book: ApplicationBook {
        didSet {
            Store.save(book.applications, as: "applications.json")
            scheduleExcelSync()
        }
    }
    var applications: [TrackedApplication] { book.applications }
    @Published var excelPath: String {
        didSet {
            defaults.set(excelPath, forKey: Keys.excelPath)
            scheduleExcelSync(delay: 0)
        }
    }
    @Published private(set) var excelStatus: ExcelStatus = .idle
    private var excelTask: Task<Void, Never>?

    static let defaultExcelPath: String = FileManager.default
        .urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("JobScout/Job Applications.xlsx").path

    // MARK: Sidebar
    @Published var sidebar: SidebarItem? = .search

    init() {
        countryCode = defaults.string(forKey: Keys.country) ?? "DE"
        englishOnly = defaults.object(forKey: Keys.englishOnly) as? Bool ?? true
        hideApplied = defaults.bool(forKey: Keys.hideApplied)
        limitPerSource = defaults.object(forKey: Keys.limit) as? Int ?? 100
        verifyLanguage = defaults.object(forKey: Keys.verify) as? Bool ?? true
        excelPath = defaults.string(forKey: Keys.excelPath) ?? Self.defaultExcelPath

        let savedSources: [String]? = Store.load("sources.json")
        enabledSources = savedSources.map(Set.init)
            ?? ["linkedin", "arbeitsagentur", "indeed", "xing", "stepstone"]
        watchlist = Store.load("watchlist.json") ?? []
        favorites = Store.load("favorites.json") ?? []
        book = ApplicationBook(Store.load("applications.json") ?? [])
        retryMissingDescriptions()
    }

    // MARK: Search

    var visibleResults: [Job] {
        results.filter { job in
            if englishOnly, verdicts[job.id] == .notEnglish { return false }
            if hideApplied, application(for: job) != nil { return false }
            return true
        }
    }

    var hiddenNonEnglish: Int {
        hiddenByTitle + results.filter { verdicts[$0.id] == .notEnglish }.count
    }

    var appliedInResults: Int {
        results.filter { application(for: $0) != nil }.count
    }

    var activeSourceNames: [String] {
        SourceRegistry.platformNames.filter {
            enabledSources.contains($0) && SourceRegistry.isAvailable($0, in: country)
        }
    }

    func makeQuery(keywords: String) -> SearchQuery {
        SearchQuery(
            keywords: keywords,
            country: country,
            datePosted: datePosted,
            jobTypes: jobTypes,
            experience: experience,
            remote: remote,
            englishOnly: englishOnly,
            limit: limitPerSource
        )
    }

    func runSearch() {
        guard !isSearching else { return }
        let keywordList = keywords
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let queries = (keywordList.isEmpty ? [""] : keywordList)
            .map { makeQuery(keywords: $0) }
        let sources = SourceRegistry.make(names: activeSourceNames, watchlist: watchlist)
        guard !sources.isEmpty else { return }

        checkTask?.cancel()
        isSearching = true
        hasSearched = true
        selection = []
        let known = descriptions
        Task {
            let result = await Aggregator.run(queries: queries, sources: sources)
            // Language verdicts need NaturalLanguage on long texts — off the main thread.
            let (verdicts, requirements) = await Task.detached(priority: .userInitiated) {
                Self.assess(result.jobs, descriptions: known)
            }.value
            self.results = result.jobs
            self.statuses = result.statuses
            self.hiddenByTitle = result.hiddenNonEnglish
            self.verdicts = verdicts
            self.germanRequirements = requirements
            self.isSearching = false
            self.startLanguageCheck()
        }
    }

    nonisolated static func assess(
        _ jobs: [Job], descriptions: [String: String]
    ) -> ([String: LanguageDetector.Verdict], [String: GermanRequirement]) {
        var verdicts: [String: LanguageDetector.Verdict] = [:]
        var requirements: [String: GermanRequirement] = [:]
        for job in jobs {
            let text = descriptions[job.id] ?? job.descriptionText
            let verdict = LanguageDetector.verdict(for: job, description: text)
            verdicts[job.id] = verdict
            if verdict == .english, !text.isEmpty {
                requirements[job.id] = GermanRequirement.detect(in: text).0
            }
        }
        return (verdicts, requirements)
    }

    // MARK: Language check (background)

    /// Reads the full description of every posting whose title looks English
    /// but isn't confirmed yet, a few at a time per site, and hides the ones
    /// that turn out to be written in another language.
    func startLanguageCheck() {
        checkTask?.cancel()
        languageCheck = LanguageCheck()
        guard englishOnly, verifyLanguage else { return }
        let pending = results.filter { verdicts[$0.id] == .unverified && descriptions[$0.id] == nil }
        guard !pending.isEmpty else { return }
        languageCheck.total = pending.count
        let bySource = Dictionary(grouping: pending, by: \.source)
        checkTask = Task {
            await withTaskGroup(of: Void.self) { group in
                for (source, jobs) in bySource {
                    group.addTask { await self.checkLanguage(source: source, jobs: jobs) }
                }
            }
        }
    }

    private func checkLanguage(source: String, jobs: [Job]) async {
        let lanes = source == "linkedin" ? 2 : 3
        var blockedInARow = 0
        var index = 0
        while index < jobs.count {
            if Task.isCancelled { return }
            let chunk = Array(jobs[index..<min(index + lanes, jobs.count)])
            index += chunk.count
            let outcomes = await withTaskGroup(of: (Job, Result<String, Error>).self) { group in
                for job in chunk {
                    group.addTask {
                        do { return (job, .success(try await JobDetails.description(for: job))) }
                        catch { return (job, .failure(error)) }
                    }
                }
                var out: [(Job, Result<String, Error>)] = []
                for await o in group { out.append(o) }
                return out
            }
            if Task.isCancelled { return }
            for (job, outcome) in outcomes {
                switch outcome {
                case .success(let text):
                    store(text, for: job)
                    blockedInARow = 0
                case .failure(let error):
                    descriptionErrors[job.id] = Self.message(error)
                    if let http = error as? HTTPError, [403, 429, 999].contains(http.status) {
                        blockedInARow += 1
                    }
                }
            }
            languageCheck.done += chunk.count
            if blockedInARow >= 3 {
                // The site is throttling us: stop politely, keep titles' verdict.
                languageCheck.stoppedSources.insert(source)
                languageCheck.done += jobs.count - index
                return
            }
            try? await Task.sleep(nanoseconds: 350_000_000)
        }
    }

    // MARK: Descriptions

    func descriptionText(for job: Job) -> String? {
        if !job.descriptionText.isEmpty { return job.descriptionText }
        if let text = descriptions[job.id] { return text }
        if let app = application(for: job), app.hasDescription { return app.job.descriptionText }
        return nil
    }

    func loadDescription(for job: Job) {
        guard descriptionText(for: job) == nil, !loadingDescriptions.contains(job.id) else { return }
        loadingDescriptions.insert(job.id)
        descriptionErrors[job.id] = nil
        Task {
            do {
                store(try await JobDetails.description(for: job), for: job)
            } catch {
                descriptionErrors[job.id] = Self.message(error)
            }
            loadingDescriptions.remove(job.id)
        }
    }

    private func store(_ text: String, for job: Job) {
        descriptions[job.id] = text
        descriptionErrors[job.id] = nil
        let verdict = LanguageDetector.verdict(for: job, description: text)
        verdicts[job.id] = verdict
        if verdict == .english {
            germanRequirements[job.id] = GermanRequirement.detect(in: text).0
        }
        // Complete an application snapshot that was saved without one.
        if let app = application(for: job), !app.hasDescription {
            updateApplication(app.id) {
                $0.job.descriptionText = text
                $0.descriptionError = nil
            }
        }
    }

    func verdict(for job: Job) -> LanguageDetector.Verdict {
        verdicts[job.id] ?? LanguageDetector.verdict(for: job)
    }

    static func message(_ error: Error) -> String {
        (error as? HTTPError)?.description
            ?? (error as? SourceError)?.message
            ?? error.localizedDescription
    }

    // MARK: Selection

    var selectedJob: Job? {
        guard selection.count == 1, let id = selection.first else { return nil }
        return results.first { $0.id == id } ?? favorites.first { $0.id == id }
    }

    func selectedJobs(in list: [Job]) -> [Job] {
        list.filter { selection.contains($0.id) }
    }

    // MARK: Applications

    /// The application for this job — the same posting, or the same company
    /// and title found through another site.
    func application(for job: Job) -> TrackedApplication? {
        book.application(for: job)
    }

    var openApplications: Int { book.openCount }

    func markApplied(_ jobs: [Job]) {
        var updated = book
        let added = updated.markApplied(jobs, country: country.name, descriptions: descriptions)
        guard !added.isEmpty else { return }
        book = updated
        for id in added where book.application(id: id)?.hasDescription == false {
            fetchApplicationDescription(id)
        }
    }

    func updateApplication(_ id: String, _ change: (inout TrackedApplication) -> Void) {
        book.update(id, change)
    }

    func removeApplication(_ id: String) {
        book.remove(id)
    }

    func fetchApplicationDescription(_ id: String) {
        guard let app = applications.first(where: { $0.id == id }) else { return }
        updateApplication(id) { $0.descriptionError = nil }
        Task {
            do {
                let text = try await JobDetails.description(for: app.job)
                descriptions[app.job.id] = text
                updateApplication(id) {
                    $0.job.descriptionText = text
                    $0.descriptionError = nil
                }
            } catch {
                let msg = Self.message(error)
                updateApplication(id) { $0.descriptionError = msg }
            }
        }
    }

    /// After a restart: finish descriptions that were still loading.
    private func retryMissingDescriptions() {
        for app in applications where !app.hasDescription && app.descriptionError == nil {
            fetchApplicationDescription(app.id)
        }
    }

    // MARK: Excel mirror

    var excelURL: URL { URL(fileURLWithPath: (excelPath as NSString).expandingTildeInPath) }

    /// Rewrites the workbook shortly after the last change (typing notes
    /// doesn't rewrite it on every keystroke).
    func scheduleExcelSync(delay: Double = 0.8) {
        excelTask?.cancel()
        let apps = applications
        let url = excelURL
        guard !apps.isEmpty || FileManager.default.fileExists(atPath: url.path) else { return }
        excelTask = Task {
            if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            guard !Task.isCancelled else { return }
            let error: String? = await Task.detached(priority: .utility) {
                do {
                    try FileManager.default.createDirectory(
                        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try ApplicationsWorkbook.build(apps).write(to: url, options: .atomic)
                    return nil
                } catch {
                    return error.localizedDescription
                }
            }.value
            excelStatus = error.map(ExcelStatus.failed) ?? .saved(Date())
        }
    }

    func openExcel() {
        if !FileManager.default.fileExists(atPath: excelURL.path) {
            try? FileManager.default.createDirectory(
                at: excelURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? ApplicationsWorkbook.build(applications).write(to: excelURL, options: .atomic)
        }
        NSWorkspace.shared.open(excelURL)
    }

    func revealExcel() {
        NSWorkspace.shared.activateFileViewerSelecting([excelURL])
    }

    func chooseExcelLocation() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = excelURL.lastPathComponent
        panel.directoryURL = excelURL.deletingLastPathComponent()
        panel.allowedContentTypes = [UTType(filenameExtension: "xlsx") ?? .data]
        panel.canCreateDirectories = true
        panel.message = "JobScout keeps this Excel file up to date with your applications."
        panel.begin { resp in
            guard resp == .OK, let url = panel.url else { return }
            Task { @MainActor in self.excelPath = url.path }
        }
    }

    // MARK: Favorites

    func isFavorite(_ job: Job) -> Bool {
        favorites.contains { $0.id == job.id }
    }

    func toggleFavorite(_ job: Job) {
        if let i = favorites.firstIndex(where: { $0.id == job.id }) {
            favorites.remove(at: i)
        } else {
            favorites.append(job)
        }
    }

    // MARK: Open / copy

    func open(_ job: Job) {
        guard let url = URL(string: job.url) else { return }
        NSWorkspace.shared.open(url)
    }

    func copyLink(_ job: Job) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(job.url, forType: .string)
    }

    // MARK: Export

    func export(_ jobs: [Job], format: ExportFormat) {
        guard !jobs.isEmpty else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "jobs.\(format.rawValue)"
        panel.canCreateDirectories = true
        let csv = Self.csv(jobs, applications: jobs.map { application(for: $0) })
        panel.begin { resp in
            guard resp == .OK, let url = panel.url else { return }
            let data: Data
            switch format {
            case .csv: data = csv.data(using: .utf8) ?? Data()
            case .json:
                let enc = JSONEncoder()
                enc.dateEncodingStrategy = .iso8601
                enc.outputFormatting = [.prettyPrinted, .sortedKeys]
                data = (try? enc.encode(jobs)) ?? Data()
            }
            try? data.write(to: url, options: .atomic)
        }
    }

    static func csv(_ jobs: [Job], applications: [TrackedApplication?]) -> String {
        func esc(_ s: String) -> String {
            "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        let df = ISO8601DateFormatter()
        var rows = ["source,title,company,location,posted,salary,employment_type,remote,language,applied_status,url"]
        for (j, app) in zip(jobs, applications) {
            let applied = app.map { "\($0.stage.label) / \($0.decision.label)" } ?? ""
            rows.append([
                j.source, j.title, j.company, j.location,
                j.posted.map { df.string(from: $0) } ?? j.postedDateRaw,
                j.salary, j.employmentType, j.remote, j.detectedLanguage, applied, j.url,
            ].map(esc).joined(separator: ","))
        }
        return rows.joined(separator: "\n")
    }
}

enum ExportFormat: String {
    case csv, json
}

let relativeFormatter: RelativeDateTimeFormatter = {
    let f = RelativeDateTimeFormatter()
    f.unitsStyle = .abbreviated
    return f
}()
