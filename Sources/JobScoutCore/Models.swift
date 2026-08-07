import Foundation

/// A single normalized job posting — same shape for every source.
public struct Job: Codable, Identifiable, Hashable, Sendable {
    public var id: String { "\(source):\(jobID)" }

    public let source: String
    public let jobID: String
    public let title: String
    public let company: String
    public let location: String
    public let url: String
    /// Raw date string as the source provided it (for display fallback).
    public var postedDateRaw: String
    /// Parsed posting date when the source provides one we can interpret.
    public var posted: Date?
    public var remote: String
    public var salary: String
    public var employmentType: String
    public var descriptionText: String

    public init(
        source: String, jobID: String, title: String, company: String,
        location: String, url: String, postedDateRaw: String = "",
        posted: Date? = nil, remote: String = "", salary: String = "",
        employmentType: String = "", descriptionText: String = ""
    ) {
        self.source = source
        self.jobID = jobID
        self.title = title
        self.company = company
        self.location = location
        self.url = url
        self.postedDateRaw = postedDateRaw
        self.posted = posted
        self.remote = remote
        self.salary = salary
        self.employmentType = employmentType
        self.descriptionText = descriptionText
    }

    /// Identity for cross-source de-duplication.
    public func dedupKey() -> String {
        func norm(_ s: String) -> String {
            s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        return "\(norm(company))|\(norm(title))|\(norm(location))"
    }

    public var detectedLanguage: String { LanguageDetector.detect(title) }
}

public enum DatePosted: String, CaseIterable, Codable, Sendable {
    case any, h24, week, month

    public var days: Int? {
        switch self {
        case .any: return nil
        case .h24: return 1
        case .week: return 7
        case .month: return 30
        }
    }

    public var cutoff: Date? {
        guard let d = days else { return nil }
        return Calendar.current.date(byAdding: .day, value: -d, to: Date())
    }

    public var label: String {
        switch self {
        case .any: return "Any time"
        case .h24: return "Past 24 hours"
        case .week: return "Past week"
        case .month: return "Past month"
        }
    }
}

public enum JobType: String, CaseIterable, Codable, Sendable {
    case fullTime = "full-time"
    case partTime = "part-time"
    case contract, temporary, internship, miniJob = "minijob"

    public var label: String {
        switch self {
        case .fullTime: return "Full-time"
        case .partTime: return "Part-time"
        case .contract: return "Contract"
        case .temporary: return "Temporary"
        case .internship: return "Internship"
        case .miniJob: return "Minijob"
        }
    }
}

public enum ExperienceLevel: String, CaseIterable, Codable, Sendable {
    case entry, mid = "mid-senior", senior

    public var label: String {
        switch self {
        case .entry: return "Entry / Junior"
        case .mid: return "Mid-level"
        case .senior: return "Senior / Lead"
        }
    }
}

public enum RemoteType: String, CaseIterable, Codable, Sendable {
    case onSite = "on-site", remote, hybrid

    public var label: String {
        switch self {
        case .onSite: return "On-site"
        case .remote: return "Remote"
        case .hybrid: return "Hybrid"
        }
    }
}

/// A platform-agnostic search request.
public struct SearchQuery: Sendable {
    public var keywords: String
    public var location: String
    public var radiusKm: Int
    public var datePosted: DatePosted
    public var jobTypes: Set<JobType>
    public var experience: Set<ExperienceLevel>
    public var remote: Set<RemoteType>
    /// Wanted posting languages ("de", "en"); empty = all.
    public var languages: Set<String>
    public var limit: Int

    public init(
        keywords: String = "", location: String = "", radiusKm: Int = 25,
        datePosted: DatePosted = .any, jobTypes: Set<JobType> = [],
        experience: Set<ExperienceLevel> = [], remote: Set<RemoteType> = [],
        languages: Set<String> = [], limit: Int = 50
    ) {
        self.keywords = keywords
        self.location = location
        self.radiusKm = radiusKm
        self.datePosted = datePosted
        self.jobTypes = jobTypes
        self.experience = experience
        self.remote = remote
        self.languages = languages
        self.limit = limit
    }
}

/// Interface every job platform adapter implements.
public protocol JobSource: Sendable {
    var name: String { get }
    func search(_ query: SearchQuery) async throws -> [Job]
}

public struct SourceStatus: Sendable, Hashable, Identifiable {
    public var id: String { source }
    public let source: String
    public let count: Int
    public let error: String?

    public init(source: String, count: Int, error: String?) {
        self.source = source
        self.count = count
        self.error = error
    }
}

public struct SearchResult: Sendable {
    public let jobs: [Job]
    public let statuses: [SourceStatus]

    public init(jobs: [Job], statuses: [SourceStatus]) {
        self.jobs = jobs
        self.statuses = statuses
    }
}
