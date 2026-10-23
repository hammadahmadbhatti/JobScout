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
            if state.hasSearched && !state.isSearching {
                summaryBar
                Divider()
            }
            resultsArea
        }
        .toolbar {
            ToolbarItemGroup {
                if state.isSearching {
                    ProgressView().controlSize(.small)
                } else if state.hasSearched {
                    Text("\(state.visibleResults.count) jobs")
                        .foregroundStyle(.secondary)
                }
                Menu {
                    Button("Export CSV…") { state.export(state.visibleResults, format: .csv) }
                    Button("Export JSON…") { state.export(state.visibleResults, format: .json) }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .disabled(state.visibleResults.isEmpty)
            }
        }
    }

    // MARK: Form

    var searchForm: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                TextField(
                    "Job title / keywords, use commas for several searches (e.g. data analyst, BI developer)",
                    text: $state.keywords
                )
                .textFieldStyle(.roundedBorder)
                .onSubmit { state.runSearch() }

                Picker("Country", selection: $state.countryCode) {
                    ForEach(Countries.all) { c in
                        Text(c.label).tag(c.code)
                    }
                }
                .labelsHidden()
                .frame(width: 190)
                .help("Searches the whole country, no city or radius needed")

                Button {
                    state.runSearch()
                } label: {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
                .disabled(state.isSearching || state.activeSourceNames.isEmpty)
                .keyboardShortcut(.defaultAction)
            }

            HStack(spacing: 10) {
                Picker("Posted:", selection: $state.datePosted) {
                    ForEach(DatePosted.allCases, id: \.self) { d in
                        Text(d.label).tag(d)
                    }
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

                Toggle("English postings only", isOn: $state.englishOnly)
                    .toggleStyle(.checkbox)
                    .help("Hide postings that aren't written in English. Indeed filters natively; for the other sites JobScout reads each posting's description to confirm it is in English.")
                Toggle("Hide jobs I applied to", isOn: $state.hideApplied)
                    .toggleStyle(.checkbox)

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
        let available = SourceRegistry.isAvailable(name, in: state.country)
        let enabled = state.enabledSources.contains(name) && available
        let status = state.statuses.first { $0.source == name }
        return Button {
            if state.enabledSources.contains(name) {
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
                if enabled, let s = status, state.hasSearched {
                    if let err = s.error {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .help(err)
                    } else {
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
        .disabled(!available)
        .help(chipHelp(name, available: available))
    }

    func chipHelp(_ name: String, available: Bool) -> String {
        if !available {
            return "\(SourceRegistry.displayName(name)) is \(SourceRegistry.availabilityNote(name) ?? "not available here"), so it is skipped for \(state.country.name)."
        }
        if name == "career-site" {
            return "Jobs pulled directly from the career pages of your watchlist companies (Companies tab)"
        }
        return ""
    }

    // MARK: Summary

    var summaryBar: some View {
        HStack(spacing: 14) {
            Label("\(state.country.label)", systemImage: "globe.europe.africa")
                .labelStyle(.titleOnly)
            if state.englishOnly {
                if state.languageCheck.isRunning {
                    HStack(spacing: 6) {
                        ProgressView(
                            value: Double(state.languageCheck.done),
                            total: Double(max(state.languageCheck.total, 1)))
                            .frame(width: 90)
                        Text("Confirming English postings \(state.languageCheck.done)/\(state.languageCheck.total)")
                    }
                    .help("Reading each posting's description to confirm it is written in English. Postings in other languages disappear as they are found.")
                }
                if state.hiddenNonEnglish > 0 {
                    Text("\(state.hiddenNonEnglish) non-English postings hidden")
                }
                if !state.languageCheck.stoppedSources.isEmpty {
                    Text("⚠️ \(state.languageCheck.stoppedSources.map(SourceRegistry.displayName).sorted().joined(separator: ", ")) paused the language check (rate limit)")
                        .foregroundStyle(.orange)
                }
            }
            if state.appliedInResults > 0 {
                Text(state.hideApplied
                     ? "\(state.appliedInResults) already applied (hidden)"
                     : "\(state.appliedInResults) already applied")
                    .foregroundStyle(.green)
            }
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }

    // MARK: Results

    var resultsArea: some View {
        let visible = state.visibleResults
        return Group {
            if visible.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: state.hasSearched ? "tray" : "briefcase")
                        .font(.system(size: 42))
                        .foregroundStyle(.quaternary)
                    if state.isSearching {
                        Text("Searching all of \(state.country.name)…").foregroundStyle(.secondary)
                    } else if state.hasSearched {
                        Text("No jobs found. Try fewer filters or different keywords.")
                            .foregroundStyle(.secondary)
                        if state.statuses.contains(where: { $0.error != nil }) {
                            Text("Some sources failed. Hover the ⚠️ icons above for details.")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    } else {
                        Text("Find English-speaking jobs anywhere in \(state.country.name) on LinkedIn, Indeed, Xing, StepStone, the Arbeitsagentur and your companies' career pages.")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 440)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    List(visible, selection: $state.selection) { job in
                        JobRow(job: job).tag(job.id)
                    }
                    .frame(minWidth: 420, idealWidth: 540)
                    .listStyle(.inset)

                    detailPane(visible)
                        .frame(minWidth: 360, idealWidth: 440, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    @ViewBuilder func detailPane(_ visible: [Job]) -> some View {
        if let job = state.selectedJob {
            JobDetailView(job: job)
        } else if state.selection.count > 1 {
            BulkSelectionView(jobs: state.selectedJobs(in: visible))
        } else {
            VStack(spacing: 6) {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 28))
                    .foregroundStyle(.quaternary)
                Text("Select a job to see details")
                    .foregroundStyle(.secondary)
                Text("⌘-click or ⇧-click to select several, then mark them as applied in one go.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

/// Shown when several results are selected.
struct BulkSelectionView: View {
    @EnvironmentObject var state: AppState
    let jobs: [Job]

    var body: some View {
        let notApplied = jobs.filter { state.application(for: $0) == nil }
        VStack(spacing: 14) {
            Image(systemName: "checklist")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("\(jobs.count) jobs selected").font(.title3.weight(.semibold))
            if notApplied.isEmpty {
                Text("You already applied to all of them.")
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    state.markApplied(notApplied)
                } label: {
                    Label("Mark \(notApplied.count) as Applied", systemImage: "paperplane")
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .controlSize(.large)
                if notApplied.count < jobs.count {
                    Text("\(jobs.count - notApplied.count) of them are already in Applications.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Each one is saved with its full description to Applications and to the Excel sheet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }
            Button {
                for job in jobs where !state.isFavorite(job) { state.toggleFavorite(job) }
            } label: {
                Label("Save all", systemImage: "star")
            }
        }
        .padding()
    }
}
