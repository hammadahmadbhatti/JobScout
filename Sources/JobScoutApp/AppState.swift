import Foundation
import SwiftUI
import AppKit
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
    case search, companies, saved
    var id: String { rawValue }

    var label: String {
        switch self {
        case .search: return "Search"
        case .companies: return "Companies"
        case .saved: return "Saved jobs"
        }
    }

    var icon: String {
        switch self {
        case .search: return "magnifyingglass"
        case .companies: return "building.2"
        case .saved: return "star"
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    // MARK: Search form
    @Published var keywords = ""
    @Published var location = ""
    @Published var radiusKm = 25
    @Published var datePosted: DatePosted = .any
    @Published var jobTypes: Set<JobType> = []
    @Published var experience: Set<ExperienceLevel> = []
    @Published var remote: Set<RemoteType> = []
    /// "": any · "de" · "en"
    @Published var language = ""
    @Published var limitPerSource = 40

    // MARK: Results
    @Published var results: [Job] = []
    @Published var statuses: [SourceStatus] = []
    @Published var isSearching = false
    @Published var selectedJobID: String?
    @Published var hasSearched = false

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
    @AppStorage("indeed.country") var indeedCountry = "DE"

    // MARK: Sidebar
    @Published var sidebar: SidebarItem? = .search

    init() {
        let savedSources: [String]? = Store.load("sources.json")
        enabledSources = savedSources.map(Set.init)
            ?? ["linkedin", "arbeitsagentur", "indeed", "xing", "stepstone"]
        watchlist = Store.load("watchlist.json") ?? []
        favorites = Store.load("favorites.json") ?? []
    }

    var selectedJob: Job? {
        results.first { $0.id == selectedJobID }
            ?? favorites.first { $0.id == selectedJobID }
    }

    func makeQuery(keywords: String, limit: Int? = nil) -> SearchQuery {
        SearchQuery(
            keywords: keywords,
            location: location.trimmingCharacters(in: .whitespaces),
            radiusKm: radiusKm,
            datePosted: datePosted,
            jobTypes: jobTypes,
            experience: experience,
            remote: remote,
            languages: language.isEmpty ? [] : [language],
            limit: limit ?? limitPerSource
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
        let sources = SourceRegistry.make(
            names: SourceRegistry.platformNames.filter { enabledSources.contains($0) },
            watchlist: watchlist,
            indeedCountry: indeedCountry
        )
        guard !sources.isEmpty else { return }

        isSearching = true
        hasSearched = true
        selectedJobID = nil
        Task {
            let result = await Aggregator.run(queries: queries, sources: sources)
            self.results = result.jobs
            self.statuses = result.statuses
            self.isSearching = false
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
        panel.begin { resp in
            guard resp == .OK, let url = panel.url else { return }
            let data: Data
            switch format {
            case .csv: data = Self.csv(jobs).data(using: .utf8) ?? Data()
            case .json:
                let enc = JSONEncoder()
                enc.dateEncodingStrategy = .iso8601
                enc.outputFormatting = [.prettyPrinted, .sortedKeys]
                data = (try? enc.encode(jobs)) ?? Data()
            }
            try? data.write(to: url, options: .atomic)
        }
    }

    static func csv(_ jobs: [Job]) -> String {
        func esc(_ s: String) -> String {
            "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        let df = ISO8601DateFormatter()
        var rows = ["source,title,company,location,posted,salary,employment_type,remote,language,url"]
        for j in jobs {
            rows.append([
                j.source, j.title, j.company, j.location,
                j.posted.map { df.string(from: $0) } ?? j.postedDateRaw,
                j.salary, j.employmentType, j.remote, j.detectedLanguage, j.url,
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
