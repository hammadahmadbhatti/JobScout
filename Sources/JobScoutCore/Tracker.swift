import Foundation

/// Where an application stands in the hiring process. Set by the user in
/// the app (never in the Excel sheet, which is only a mirror).
public enum ApplicationStage: String, Codable, CaseIterable, Sendable {
    case applied
    case followedUp = "followed-up"
    case phoneScreen = "phone-screen"
    case interview
    case assessment
    case finalInterview = "final-interview"

    public var label: String {
        switch self {
        case .applied: return "Applied"
        case .followedUp: return "Followed up"
        case .phoneScreen: return "Phone screen"
        case .interview: return "Interview"
        case .assessment: return "Assessment / task"
        case .finalInterview: return "Final interview"
        }
    }
}

/// The outcome of an application.
public enum ApplicationDecision: String, Codable, CaseIterable, Sendable {
    case pending
    case offer
    case accepted
    case declined
    case rejected
    case withdrawn
    case noResponse = "no-response"

    public var label: String {
        switch self {
        case .pending: return "Awaiting decision"
        case .offer: return "Offer received"
        case .accepted: return "Offer accepted"
        case .declined: return "Offer declined"
        case .rejected: return "Rejected"
        case .withdrawn: return "Withdrawn"
        case .noResponse: return "No response"
        }
    }

    /// The process is over (nothing left to wait for).
    public var isClosed: Bool {
        switch self {
        case .pending, .offer: return false
        default: return true
        }
    }
}

public struct StatusChange: Codable, Hashable, Sendable {
    public var date: Date
    public var text: String

    public init(date: Date, text: String) {
        self.date = date
        self.text = text
    }
}

/// A job the user applied to, with a snapshot of the posting (including
/// its full description) so the record survives the posting going offline.
public struct TrackedApplication: Codable, Identifiable, Hashable, Sendable {
    public var id: String { job.id }
    public var job: Job
    /// Country the search covered when the user applied.
    public var country: String
    public var appliedOn: Date
    public private(set) var stage: ApplicationStage
    public private(set) var decision: ApplicationDecision
    public var decisionDate: Date?
    public var notes: String
    public var updatedAt: Date
    public private(set) var history: [StatusChange]
    /// Why the full description couldn't be fetched yet (nil = fine).
    public var descriptionError: String?

    public init(job: Job, country: String, appliedOn: Date = Date()) {
        self.job = job
        self.country = country
        self.appliedOn = appliedOn
        self.stage = .applied
        self.decision = .pending
        self.notes = ""
        self.updatedAt = appliedOn
        self.history = [StatusChange(date: appliedOn, text: "Applied")]
    }

    public mutating func setStage(_ newStage: ApplicationStage, at date: Date = Date()) {
        guard newStage != stage else { return }
        stage = newStage
        history.append(StatusChange(date: date, text: "Status: \(newStage.label)"))
        updatedAt = date
    }

    public mutating func setDecision(_ newDecision: ApplicationDecision, at date: Date = Date()) {
        guard newDecision != decision else { return }
        decision = newDecision
        decisionDate = newDecision == .pending ? nil : date
        history.append(StatusChange(date: date, text: "Decision: \(newDecision.label)"))
        updatedAt = date
    }

    public mutating func setAppliedOn(_ date: Date) {
        appliedOn = date
        if !history.isEmpty, history[0].text == "Applied" { history[0].date = date }
        updatedAt = Date()
    }

    public var hasDescription: Bool {
        !job.descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// All applications plus the lookups the app needs. A job counts as applied
/// when it is the same posting, or the same company and title found on
/// another site (LinkedIn and Indeed often carry the same ad).
public struct ApplicationBook: Sendable {
    public private(set) var applications: [TrackedApplication]
    private var byID: [String: Int] = [:]
    private var byKey: [String: Int] = [:]

    public init(_ applications: [TrackedApplication] = []) {
        self.applications = applications
        reindex()
    }

    private mutating func reindex() {
        byID = [:]
        byKey = [:]
        for (i, app) in applications.enumerated() {
            byID[app.id] = i
            if byKey[app.job.trackingKey] == nil { byKey[app.job.trackingKey] = i }
        }
    }

    public func application(for job: Job) -> TrackedApplication? {
        if let i = byID[job.id] { return applications[i] }
        if let i = byKey[job.trackingKey] { return applications[i] }
        return nil
    }

    public func application(id: String) -> TrackedApplication? {
        byID[id].map { applications[$0] }
    }

    public var openCount: Int { applications.filter { !$0.decision.isClosed }.count }

    /// Adds the jobs not applied to yet; returns the ids that were added.
    /// `descriptions` fills in full descriptions already fetched for them.
    @discardableResult
    public mutating func markApplied(
        _ jobs: [Job], country: String, descriptions: [String: String] = [:], at date: Date = Date()
    ) -> [String] {
        var added: [String] = []
        for job in jobs where application(for: job) == nil {
            var snapshot = job
            if snapshot.descriptionText.isEmpty, let text = descriptions[job.id] {
                snapshot.descriptionText = text
            }
            applications.append(TrackedApplication(job: snapshot, country: country, appliedOn: date))
            reindex()
            added.append(job.id)
        }
        return added
    }

    public mutating func update(_ id: String, _ change: (inout TrackedApplication) -> Void) {
        guard let i = byID[id] else { return }
        change(&applications[i])
        reindex()
    }

    public mutating func remove(_ id: String) {
        applications.removeAll { $0.id == id }
        reindex()
    }
}

/// Builds the applications workbook: one row per application (newest first)
/// with the complete job description, plus a summary sheet.
public enum ApplicationsWorkbook {
    public static let headers = [
        "#", "Date applied", "Job title", "Company", "Location", "Country", "Source",
        "Status", "Decision", "Decision date", "Last updated", "Notes", "Status history",
        "Salary", "Employment type", "Posted", "Job link", "Job description",
    ]
    static let widths: [Double] = [
        5, 12, 36, 24, 22, 14, 13, 18, 18, 13, 16, 36, 40, 18, 16, 12, 40, 110,
    ]

    public static func build(_ applications: [TrackedApplication], generated: Date = Date()) -> Data {
        XLSX.workbook([applicationsSheet(applications), summarySheet(applications, generated: generated)])
    }

    static func applicationsSheet(_ applications: [TrackedApplication]) -> XLSX.Sheet {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")
        let sorted = applications.sorted { $0.appliedOn > $1.appliedOn }

        var rows: [[XLSX.Cell]] = [headers.map { .text($0, .header) }]
        for (i, app) in sorted.enumerated() {
            let j = app.job
            let history = app.history
                .map { "\(df.string(from: $0.date))  \($0.text)" }
                .joined(separator: "\n")
            var description = j.descriptionText
            if description.isEmpty {
                description = app.descriptionError.map { "(Description unavailable: \($0))" }
                    ?? "(Fetching description…)"
            }
            rows.append([
                .number(Double(i + 1)),
                .date(app.appliedOn),
                .text(j.title, .wrap),
                .text(j.company, .wrap),
                .text(j.location, .wrap),
                .text(app.country),
                .text(SourceRegistry.displayName(j.source)),
                .text(app.stage.label, .wrap),
                .text(app.decision.label, decisionStyle(app.decision)),
                app.decisionDate.map { .date($0) } ?? .empty,
                .date(app.updatedAt, .dateTime),
                .text(app.notes, .wrap),
                .text(history, .wrap),
                .text(j.salary, .wrap),
                .text(j.employmentType, .wrap),
                j.posted.map { .date($0) } ?? .text(j.postedDateRaw),
                .link(j.url),
                .text(description, .wrap),
            ])
        }
        return XLSX.Sheet(
            name: "Applications", columnWidths: widths, rows: rows,
            freezeHeader: true, autoFilter: true, bodyRowHeight: 90)
    }

    static func summarySheet(_ applications: [TrackedApplication], generated: Date) -> XLSX.Sheet {
        var rows: [[XLSX.Cell]] = [
            [.text("JobScout applications", .title)],
            [.text("Updated"), .date(generated, .dateTime)],
            [.text("Total applications"), .number(Double(applications.count))],
            [.text("Still open"), .number(Double(applications.filter { !$0.decision.isClosed }.count))],
            [],
            [.text("Decision", .header), .text("Count", .header)],
        ]
        for d in ApplicationDecision.allCases {
            rows.append([.text(d.label, decisionStyle(d)), .number(Double(applications.filter { $0.decision == d }.count))])
        }
        rows.append([])
        rows.append([.text("Status", .header), .text("Count", .header)])
        for s in ApplicationStage.allCases {
            rows.append([.text(s.label), .number(Double(applications.filter { $0.stage == s }.count))])
        }
        rows.append([])
        rows.append([.text("This file is rewritten by JobScout whenever an application changes. Update statuses in the app, not here.", .text)])
        return XLSX.Sheet(name: "Summary", columnWidths: [26, 18], rows: rows)
    }

    static func decisionStyle(_ d: ApplicationDecision) -> XLSX.Style {
        switch d {
        case .pending: return .yellow
        case .offer, .accepted: return .green
        case .rejected: return .red
        case .declined, .withdrawn, .noResponse: return .gray
        }
    }
}
