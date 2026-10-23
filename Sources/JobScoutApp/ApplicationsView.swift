import SwiftUI
import JobScoutCore

/// Every job you applied to. Status and decision are set here (or in the job
/// detail pane); the Excel file is rewritten automatically after each change.
struct ApplicationsView: View {
    @EnvironmentObject var state: AppState
    @State private var selection: Set<String> = []
    @State private var filter: Filter = .all
    @State private var searchText = ""
    @State private var confirmRemove: TrackedApplication?

    enum Filter: String, CaseIterable {
        case all = "All", open = "Open", closed = "Closed"
    }

    var filtered: [TrackedApplication] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        return state.applications
            .filter { app in
                switch filter {
                case .all: return true
                case .open: return !app.decision.isClosed
                case .closed: return app.decision.isClosed
                }
            }
            .filter { app in
                q.isEmpty || app.job.title.lowercased().contains(q)
                    || app.job.company.lowercased().contains(q)
                    || app.notes.lowercased().contains(q)
            }
            .sorted { $0.appliedOn > $1.appliedOn }
    }

    var body: some View {
        VStack(spacing: 0) {
            excelBar
            Divider()
            if state.applications.isEmpty {
                emptyState
            } else {
                HSplitView {
                    table
                        .frame(minWidth: 520, idealWidth: 640)
                    detail
                        .frame(minWidth: 360, idealWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Picker("Show", selection: $filter) {
                    ForEach(Filter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                TextField("Filter", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                Button {
                    state.openExcel()
                } label: {
                    Label("Open in Excel", systemImage: "tablecells")
                }
                .help("Open the Excel sheet (it updates automatically)")
            }
        }
        .confirmationDialog(
            "Remove this application?",
            isPresented: Binding(get: { confirmRemove != nil }, set: { if !$0 { confirmRemove = nil } }),
            presenting: confirmRemove
        ) { app in
            Button("Remove “\(app.job.title)”", role: .destructive) {
                selection.remove(app.id)
                state.removeApplication(app.id)
            }
        } message: { _ in
            Text("It disappears from JobScout and from the Excel sheet.")
        }
    }

    // MARK: Excel bar

    var excelBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "tablecells")
                .foregroundStyle(.green)
            Text(state.excelURL.lastPathComponent)
                .fontWeight(.medium)
            Text(state.excelURL.deletingLastPathComponent().path
                .replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            switch state.excelStatus {
            case .idle:
                EmptyView()
            case .saved(let date):
                Text("· updated \(date.formatted(date: .omitted, time: .shortened))")
                    .foregroundStyle(.secondary)
            case .failed(let message):
                Text("· couldn't write the file: \(message)")
                    .foregroundStyle(.red)
                    .lineLimit(1)
                Button("Retry") { state.scheduleExcelSync(delay: 0) }
                    .controlSize(.small)
            }
            Spacer()
            Button("Show in Finder") { state.revealExcel() }
                .controlSize(.small)
                .disabled(state.applications.isEmpty)
            Button("Change…") { state.chooseExcelLocation() }
                .controlSize(.small)
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .help("JobScout rewrites this file whenever an application changes. Edit statuses here, not in Excel. If the file is open in Excel, reopen it to see the latest changes.")
    }

    // MARK: Table

    var table: some View {
        Table(filtered, selection: $selection) {
            TableColumn("Job") { app in
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.job.title).fontWeight(.semibold).lineLimit(1)
                    Text([app.job.company, app.job.location].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.vertical, 2)
            }
            .width(min: 180, ideal: 260)
            TableColumn("Applied") { app in
                Text(app.appliedOn.formatted(date: .abbreviated, time: .omitted))
                    .foregroundStyle(.secondary)
            }
            .width(min: 70, ideal: 90)
            TableColumn("Status") { app in
                Picker("", selection: Binding(
                    get: { app.stage },
                    set: { s in state.updateApplication(app.id) { $0.setStage(s) } })
                ) {
                    ForEach(ApplicationStage.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .controlSize(.small)
            }
            .width(min: 120, ideal: 140)
            TableColumn("Decision") { app in
                Picker("", selection: Binding(
                    get: { app.decision },
                    set: { d in state.updateApplication(app.id) { $0.setDecision(d) } })
                ) {
                    ForEach(ApplicationDecision.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .controlSize(.small)
                .tint(app.decision.color)
            }
            .width(min: 120, ideal: 145)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            if let id = ids.first, ids.count == 1,
               let app = state.applications.first(where: { $0.id == id }) {
                Button("Open Job in Browser") { state.open(app.job) }
                Button("Copy Link") { state.copyLink(app.job) }
                Divider()
                Button("Remove Application…", role: .destructive) { confirmRemove = app }
            }
        }
    }

    // MARK: Detail

    @ViewBuilder var detail: some View {
        if selection.count == 1, let id = selection.first,
           let app = state.applications.first(where: { $0.id == id }) {
            ApplicationDetailView(application: app, onRemove: { confirmRemove = app })
        } else {
            VStack(spacing: 8) {
                Image(systemName: "checklist")
                    .font(.system(size: 30))
                    .foregroundStyle(.quaternary)
                Text("Select an application to update it")
                    .foregroundStyle(.secondary)
                summary
            }
            .padding()
        }
    }

    var summary: some View {
        let apps = state.applications
        return Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
            GridRow {
                Text("Total").foregroundStyle(.secondary)
                Text("\(apps.count)")
            }
            GridRow {
                Text("Still open").foregroundStyle(.secondary)
                Text("\(state.openApplications)")
            }
            ForEach(ApplicationDecision.allCases.filter { d in apps.contains { $0.decision == d } }, id: \.self) { d in
                GridRow {
                    Text(d.label).foregroundStyle(d.color)
                    Text("\(apps.filter { $0.decision == d }.count)")
                }
            }
        }
        .font(.callout)
        .padding(.top, 10)
    }

    var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checklist")
                .font(.system(size: 42))
                .foregroundStyle(.quaternary)
            Text("No applications yet")
                .font(.headline)
            Text("In Search, click ✈︎ on a job (or select several and use “Mark as Applied”). JobScout saves each one with its full description, keeps this list, and writes it to an Excel sheet that updates whenever you change a status.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
            Button("Go to Search") { state.sidebar = .search }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ApplicationDetailView: View {
    @EnvironmentObject var state: AppState
    let application: TrackedApplication
    let onRemove: () -> Void
    @State private var notes = ""

    var body: some View {
        let job = application.job
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(job.title).font(.title2.weight(.bold))
                    Text([job.company, job.location, application.country]
                        .filter { !$0.isEmpty }.joined(separator: " · "))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        SourceBadge(source: job.source)
                        AppliedBadge(application: application)
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        state.open(job)
                    } label: {
                        Label("Open Posting", systemImage: "safari")
                    }
                    .buttonStyle(.borderedProminent)
                    Button {
                        state.copyLink(job)
                    } label: {
                        Label("Copy Link", systemImage: "doc.on.doc")
                    }
                    Spacer()
                    Button(role: .destructive, action: onRemove) {
                        Label("Remove", systemImage: "trash")
                    }
                }

                Divider()
                ApplicationControls(application: application)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Notes").font(.headline)
                    TextEditor(text: $notes)
                        .font(.callout)
                        .frame(minHeight: 70, maxHeight: 140)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25)))
                        .onChange(of: notes) { value in
                            guard value != application.notes else { return }
                            state.updateApplication(application.id) {
                                $0.notes = value
                                $0.updatedAt = Date()
                            }
                        }
                    Text("Contacts, interview dates, feedback… saved to the Excel sheet too.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("History").font(.headline)
                    ForEach(Array(application.history.enumerated().reversed()), id: \.offset) { _, change in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(change.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 130, alignment: .leading)
                            Text(change.text).font(.callout)
                        }
                    }
                }

                Divider()
                HStack {
                    Text("Job description").font(.headline)
                    Spacer()
                    if !application.hasDescription {
                        Button("Fetch again") { state.fetchApplicationDescription(application.id) }
                            .controlSize(.small)
                    }
                }
                if application.hasDescription {
                    Text(job.descriptionText)
                        .font(.callout)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if let error = application.descriptionError {
                    Text(error).font(.caption).foregroundStyle(.orange)
                } else {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Fetching the full description…").foregroundStyle(.secondary)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .onAppear { notes = application.notes }
        .onChange(of: application.id) { _ in notes = application.notes }
    }
}
