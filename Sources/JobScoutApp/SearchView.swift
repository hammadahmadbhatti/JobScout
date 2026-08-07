import SwiftUI
import JobScoutCore

struct SearchView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            searchForm
            Divider()
            sourceRow
            Divider()
            resultsArea
        }
        .toolbar {
            ToolbarItemGroup {
                if state.isSearching {
                    ProgressView().controlSize(.small)
                } else if state.hasSearched {
                    Text("\(state.results.count) jobs")
                        .foregroundStyle(.secondary)
                }
                Menu {
                    Button("Export CSV…") { state.export(state.results, format: .csv) }
                    Button("Export JSON…") { state.export(state.results, format: .json) }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .disabled(state.results.isEmpty)
            }
        }
    }

    // MARK: Form

    var searchForm: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                TextField(
                    "Job title / keywords — use commas for multiple searches (e.g. Koch, Kellner)",
                    text: $state.keywords
                )
                .textFieldStyle(.roundedBorder)
                .onSubmit { state.runSearch() }

                TextField("Location", text: $state.location)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 170)
                    .onSubmit { state.runSearch() }

                Button {
                    state.runSearch()
                } label: {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
                .disabled(state.isSearching)
                .keyboardShortcut(.defaultAction)
            }

            HStack(spacing: 10) {
                Picker("Posted:", selection: $state.datePosted) {
                    ForEach(DatePosted.allCases, id: \.self) { d in
                        Text(d.label).tag(d)
                    }
                }
                .fixedSize()

                Picker("Language:", selection: $state.language) {
                    Text("Any").tag("")
                    Text("German 🇩🇪").tag("de")
                    Text("English 🇬🇧").tag("en")
                }
                .fixedSize()

                multiMenu(
                    "Job type", selection: $state.jobTypes,
                    all: JobType.allCases, label: \.label)
                multiMenu(
                    "Experience", selection: $state.experience,
                    all: ExperienceLevel.allCases, label: \.label)
                multiMenu(
                    "Workplace", selection: $state.remote,
                    all: RemoteType.allCases, label: \.label)

                Stepper(
                    "Radius: \(state.radiusKm) km",
                    value: $state.radiusKm, in: 5...100, step: 5
                )
                .fixedSize()

                Spacer()
            }
            .controlSize(.small)
        }
        .padding(12)
    }

    func multiMenu<T: Hashable>(
        _ title: String, selection: Binding<Set<T>>,
        all: [T], label: KeyPath<T, String>
    ) -> some View {
        Menu {
            ForEach(all, id: \.self) { item in
                Button {
                    if selection.wrappedValue.contains(item) {
                        selection.wrappedValue.remove(item)
                    } else {
                        selection.wrappedValue.insert(item)
                    }
                } label: {
                    HStack {
                        if selection.wrappedValue.contains(item) {
                            Image(systemName: "checkmark")
                        }
                        Text(item[keyPath: label])
                    }
                }
            }
            if !selection.wrappedValue.isEmpty {
                Divider()
                Button("Clear") { selection.wrappedValue = [] }
            }
        } label: {
            Text(
                selection.wrappedValue.isEmpty
                    ? title
                    : "\(title) (\(selection.wrappedValue.count))")
        }
        .fixedSize()
    }

    // MARK: Sources

    var sourceRow: some View {
        HStack(spacing: 8) {
            Text("Sources:")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(SourceRegistry.platformNames, id: \.self) { name in
                sourceChip(name)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    func sourceChip(_ name: String) -> some View {
        let enabled = state.enabledSources.contains(name)
        let status = state.statuses.first { $0.source == name }
        return Button {
            if enabled {
                state.enabledSources.remove(name)
            } else {
                state.enabledSources.insert(name)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: enabled ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(enabled ? Color.accentColor : .secondary)
                Text(SourceRegistry.displayName(name))
                if name == "career-site" && !state.watchlist.isEmpty {
                    Text("(\(state.watchlist.count))").foregroundStyle(.secondary)
                }
                if enabled, let s = status {
                    if let err = s.error {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .help(err)
                    } else if state.hasSearched {
                        Text("\(s.count)")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .background(Capsule().fill(Color.secondary.opacity(0.15)))
                    }
                }
            }
            .font(.callout)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help(
            name == "career-site"
                ? "Jobs pulled directly from the career pages of your watchlist companies (Companies tab)"
                : "")
    }

    // MARK: Results

    var resultsArea: some View {
        Group {
            if state.results.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: state.hasSearched ? "tray" : "briefcase")
                        .font(.system(size: 42))
                        .foregroundStyle(.quaternary)
                    if state.isSearching {
                        Text("Searching…").foregroundStyle(.secondary)
                    } else if state.hasSearched {
                        Text("No jobs found — try fewer filters or different keywords.")
                            .foregroundStyle(.secondary)
                        if state.statuses.contains(where: { $0.error != nil }) {
                            Text("Some sources failed — hover the ⚠️ icons above for details.")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    } else {
                        Text("Search across LinkedIn, Arbeitsagentur, Indeed, Xing, StepStone and your companies' career pages.")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 420)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    List(state.results, selection: $state.selectedJobID) { job in
                        JobRow(job: job).tag(job.id)
                    }
                    .frame(minWidth: 400, idealWidth: 520)
                    .listStyle(.inset)

                    if let job = state.selectedJob {
                        JobDetailView(job: job)
                            .frame(minWidth: 340, idealWidth: 420)
                    } else {
                        VStack {
                            Image(systemName: "sidebar.right")
                                .font(.system(size: 28))
                                .foregroundStyle(.quaternary)
                            Text("Select a job to see details")
                                .foregroundStyle(.secondary)
                        }
                        .frame(minWidth: 340, maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
    }
}
