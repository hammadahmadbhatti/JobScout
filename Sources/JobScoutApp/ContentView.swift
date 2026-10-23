import SwiftUI
import JobScoutCore

struct ContentView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $state.sidebar) { item in
                Label {
                    HStack {
                        Text(item.label)
                        Spacer()
                        if let count = badgeCount(item), count > 0 {
                            Text("\(count)")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.secondary.opacity(0.2)))
                        }
                    }
                } icon: {
                    Image(systemName: item.icon)
                }
                .tag(item)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
        } detail: {
            switch state.sidebar ?? .search {
            case .search: SearchView()
            case .applications: ApplicationsView()
            case .companies: WatchlistView()
            case .saved: SavedView()
            }
        }
        .navigationTitle("JobScout")
        .onChange(of: state.sidebar) { _ in state.selection = [] }
    }

    func badgeCount(_ item: SidebarItem) -> Int? {
        switch item {
        case .search: return nil
        case .applications: return state.applications.count
        case .companies: return state.watchlist.count
        case .saved: return state.favorites.count
        }
    }
}

// MARK: - Shared bits

struct SourceBadge: View {
    let source: String

    static let colors: [String: Color] = [
        "linkedin": .blue,
        "arbeitsagentur": .red,
        "indeed": .indigo,
        "xing": .green,
        "stepstone": .teal,
        "career-site": .orange,
    ]

    var body: some View {
        Text(SourceRegistry.displayName(source))
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule().fill((Self.colors[source] ?? .gray).opacity(0.18)))
            .foregroundStyle(Self.colors[source] ?? .gray)
    }
}

extension ApplicationDecision {
    var color: Color {
        switch self {
        case .pending: return .blue
        case .offer, .accepted: return .green
        case .rejected: return .red
        case .declined, .withdrawn, .noResponse: return .gray
        }
    }
}

/// "✓ Applied 12 Oct · Interview" — shown wherever a job you applied to appears.
struct AppliedBadge: View {
    let application: TrackedApplication

    var body: some View {
        let d = application.decision
        let text = d == .pending ? application.stage.label : d.label
        HStack(spacing: 3) {
            Image(systemName: d.isClosed && d != .accepted ? "checkmark.circle" : "checkmark.circle.fill")
            Text("Applied \(application.appliedOn.formatted(.dateTime.day().month(.abbreviated))) · \(text)")
        }
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(d.color.opacity(0.16)))
        .foregroundStyle(d.color)
        .help("You applied on \(application.appliedOn.formatted(date: .long, time: .omitted)). Status: \(application.stage.label). Decision: \(d.label).")
    }
}

struct GermanTag: View {
    let requirement: GermanRequirement

    var body: some View {
        switch requirement {
        case .required:
            Text("German required")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Capsule().fill(Color.orange.opacity(0.18)))
                .foregroundStyle(.orange)
                .help("The description asks for German language skills")
        case .plus:
            Text("German a plus")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .help("German is mentioned as a plus, not a requirement")
        case .notMentioned:
            EmptyView()
        }
    }
}

struct JobRow: View {
    @EnvironmentObject var state: AppState
    let job: Job

    var body: some View {
        let application = state.application(for: job)
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .top) {
                Text(job.title)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                Spacer(minLength: 8)
                if application == nil {
                    Button {
                        state.markApplied([job])
                    } label: {
                        Image(systemName: "paperplane")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Mark as applied (adds it to Applications and the Excel sheet)")
                }
                Button {
                    state.toggleFavorite(job)
                } label: {
                    Image(systemName: state.isFavorite(job) ? "star.fill" : "star")
                        .foregroundStyle(state.isFavorite(job) ? .yellow : .secondary)
                }
                .buttonStyle(.plain)
                .help(state.isFavorite(job) ? "Remove from saved jobs" : "Save job")
            }
            HStack(spacing: 4) {
                if !job.company.isEmpty { Text(job.company) }
                if !job.company.isEmpty && !job.location.isEmpty { Text("·") }
                if !job.location.isEmpty { Text(job.location) }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            HStack(spacing: 6) {
                SourceBadge(source: job.source)
                if let app = application {
                    AppliedBadge(application: app)
                }
                if let req = state.germanRequirements[job.id] {
                    GermanTag(requirement: req)
                }
                if let posted = job.posted {
                    Text(relativeFormatter.localizedString(for: posted, relativeTo: Date()))
                        .foregroundStyle(.secondary)
                } else if !job.postedDateRaw.isEmpty {
                    Text(job.postedDateRaw).foregroundStyle(.secondary)
                }
                if !job.salary.isEmpty {
                    Text(job.salary).foregroundStyle(.green)
                }
                if !job.employmentType.isEmpty {
                    Text(job.employmentType).foregroundStyle(.secondary)
                }
                if !job.remote.isEmpty {
                    Text(job.remote).foregroundStyle(.purple)
                }
            }
            .font(.caption)
            .lineLimit(1)
        }
        .padding(.vertical, 3)
        .contextMenu {
            Button("Open in Browser") { state.open(job) }
            Button("Copy Link") { state.copyLink(job) }
            Divider()
            if application == nil {
                let selected = state.selection.contains(job.id) && state.selection.count > 1
                Button(selected ? "Mark \(state.selection.count) Selected as Applied" : "Mark as Applied") {
                    if selected {
                        state.markApplied(state.selectedJobs(in: state.results + state.favorites))
                    } else {
                        state.markApplied([job])
                    }
                }
            } else {
                Button("Show in Applications") { state.sidebar = .applications }
            }
            Button(state.isFavorite(job) ? "Remove from Saved" : "Save Job") {
                state.toggleFavorite(job)
            }
        }
    }
}

/// Status & decision controls for an application — the same controls appear
/// in the job detail pane and the Applications tab.
struct ApplicationControls: View {
    @EnvironmentObject var state: AppState
    let application: TrackedApplication

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow {
                Text("Applied on").foregroundStyle(.secondary)
                DatePicker(
                    "", selection: Binding(
                        get: { application.appliedOn },
                        set: { d in state.updateApplication(application.id) { $0.setAppliedOn(d) } }),
                    displayedComponents: .date)
                    .labelsHidden()
                    .fixedSize()
            }
            GridRow {
                Text("Status").foregroundStyle(.secondary)
                Picker("", selection: Binding(
                    get: { application.stage },
                    set: { s in state.updateApplication(application.id) { $0.setStage(s) } })
                ) {
                    ForEach(ApplicationStage.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }
            GridRow {
                Text("Decision").foregroundStyle(.secondary)
                HStack {
                    Picker("", selection: Binding(
                        get: { application.decision },
                        set: { d in state.updateApplication(application.id) { $0.setDecision(d) } })
                    ) {
                        ForEach(ApplicationDecision.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    if let date = application.decisionDate {
                        Text("on \(date.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .font(.callout)
    }
}

struct JobDetailView: View {
    @EnvironmentObject var state: AppState
    let job: Job

    var body: some View {
        let application = state.application(for: job)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(job.title).font(.title2.weight(.bold))
                    HStack(spacing: 6) {
                        if !job.company.isEmpty {
                            Text(job.company).font(.headline)
                        }
                        if !job.location.isEmpty {
                            Text("·").foregroundStyle(.secondary)
                            Text(job.location).foregroundStyle(.secondary)
                        }
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        state.open(job)
                    } label: {
                        Label("Open in Browser", systemImage: "safari")
                    }
                    .buttonStyle(.borderedProminent)
                    if application == nil {
                        Button {
                            state.markApplied([job])
                        } label: {
                            Label("Mark as Applied", systemImage: "paperplane")
                        }
                        .tint(.green)
                        .buttonStyle(.borderedProminent)
                        .help("Adds the job, with its full description, to Applications and the Excel sheet")
                    }
                    Button {
                        state.copyLink(job)
                    } label: {
                        Label("Copy Link", systemImage: "doc.on.doc")
                    }
                    Button {
                        state.toggleFavorite(job)
                    } label: {
                        Label(
                            state.isFavorite(job) ? "Saved" : "Save",
                            systemImage: state.isFavorite(job) ? "star.fill" : "star")
                    }
                }

                if let app = application {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            AppliedBadge(application: app)
                            if app.id != job.id {
                                Text("(applied via \(SourceRegistry.displayName(app.job.source)))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Open in Applications") { state.sidebar = .applications }
                                .controlSize(.small)
                        }
                        ApplicationControls(application: app)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(app.decision.color.opacity(0.07)))
                }

                Divider()

                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                    GridRow {
                        Text("Source").foregroundStyle(.secondary)
                        SourceBadge(source: job.source)
                    }
                    if let posted = job.posted {
                        GridRow {
                            Text("Posted").foregroundStyle(.secondary)
                            Text("\(posted.formatted(date: .abbreviated, time: .omitted)) (\(relativeFormatter.localizedString(for: posted, relativeTo: Date())))")
                        }
                    } else if !job.postedDateRaw.isEmpty {
                        GridRow {
                            Text("Posted").foregroundStyle(.secondary)
                            Text(job.postedDateRaw)
                        }
                    }
                    if !job.employmentType.isEmpty {
                        GridRow {
                            Text("Type").foregroundStyle(.secondary)
                            Text(job.employmentType)
                        }
                    }
                    if !job.salary.isEmpty {
                        GridRow {
                            Text("Salary").foregroundStyle(.secondary)
                            Text(job.salary).foregroundStyle(.green)
                        }
                    }
                    if !job.remote.isEmpty {
                        GridRow {
                            Text("Workplace").foregroundStyle(.secondary)
                            Text(job.remote)
                        }
                    }
                    GridRow {
                        Text("Language").foregroundStyle(.secondary)
                        languageText
                    }
                    if let req = state.germanRequirements[job.id] {
                        GridRow {
                            Text("German").foregroundStyle(.secondary)
                            Text(req.label)
                                .foregroundStyle(req == .required ? .orange : .secondary)
                        }
                    }
                    GridRow {
                        Text("Link").foregroundStyle(.secondary)
                        Text(job.url)
                            .font(.caption)
                            .textSelection(.enabled)
                            .lineLimit(2)
                    }
                }
                .font(.callout)

                Divider()
                Text("Description").font(.headline)
                descriptionBody
                Spacer()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .task(id: job.id) { state.loadDescription(for: job) }
    }

    @ViewBuilder var languageText: some View {
        switch state.verdict(for: job) {
        case .english: Text("English 🇬🇧")
        case .notEnglish: Text("Not in English")
        case .unverified: Text("English title (not yet confirmed from the description)")
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder var descriptionBody: some View {
        if let text = state.descriptionText(for: job) {
            Text(text)
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if state.loadingDescriptions.contains(job.id) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Loading the full description…").foregroundStyle(.secondary)
            }
        } else if let error = state.descriptionErrors[job.id] {
            VStack(alignment: .leading, spacing: 6) {
                Text(error).font(.caption).foregroundStyle(.orange)
                Button("Try again") { state.loadDescription(for: job) }
                    .controlSize(.small)
            }
        }
    }
}
