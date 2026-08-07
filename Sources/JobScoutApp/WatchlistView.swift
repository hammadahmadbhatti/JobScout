import SwiftUI
import JobScoutCore

/// Manage companies whose career pages are scraped directly (via their ATS
/// public feeds: Personio, Greenhouse, Lever, Recruitee, SmartRecruiters).
struct WatchlistView: View {
    @EnvironmentObject var state: AppState
    @State private var showAdd = false
    @State private var companyJobs: [Job] = []
    @State private var loadingJobs = false
    @State private var loadError: String?

    var body: some View {
        VStack(spacing: 0) {
            if state.watchlist.isEmpty {
                emptyState
            } else {
                listArea
            }
        }
        .toolbar {
            ToolbarItemGroup {
                if !companyJobs.isEmpty {
                    Menu {
                        Button("Export CSV…") { state.export(companyJobs, format: .csv) }
                        Button("Export JSON…") { state.export(companyJobs, format: .json) }
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                }
                Button {
                    loadAllJobs()
                } label: {
                    if loadingJobs {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Load open positions", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(state.watchlist.isEmpty || loadingJobs)
                Button {
                    showAdd = true
                } label: {
                    Label("Add company", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddCompanySheet()
        }
    }

    var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "building.2")
                .font(.system(size: 42))
                .foregroundStyle(.quaternary)
            Text("Watch companies and get their jobs straight from their career pages")
                .font(.headline)
            Text("Add a company by name or paste its careers-page URL. JobScout auto-detects the job system it uses (Personio, Greenhouse, Lever, Recruitee, SmartRecruiters) — very common among German companies — and reads its public job feed. No login, no API key.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
            Button {
                showAdd = true
            } label: {
                Label("Add your first company", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var listArea: some View {
        HSplitView {
            List {
                Section("Watchlist") {
                    ForEach(state.watchlist) { company in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(company.name).fontWeight(.medium)
                                HStack(spacing: 6) {
                                    Text(company.ats.label)
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(Capsule().fill(Color.orange.opacity(0.18)))
                                        .foregroundStyle(.orange)
                                    Text(company.host.isEmpty ? company.slug : company.host)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                        }
                        .contextMenu {
                            Button("Remove") {
                                state.watchlist.removeAll { $0.id == company.id }
                                companyJobs.removeAll { $0.company == company.name }
                            }
                        }
                    }
                }
            }
            .frame(minWidth: 240, idealWidth: 280, maxWidth: 400)

            VStack(spacing: 0) {
                if loadingJobs {
                    ProgressView("Fetching career pages…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let err = loadError {
                    Text(err).foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if companyJobs.isEmpty {
                    VStack(spacing: 8) {
                        Text("Press “Load open positions” to fetch every job these companies currently offer.")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 380)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(companyJobs) { job in
                        JobRow(job: job)
                            .onTapGesture(count: 2) { state.open(job) }
                    }
                    .listStyle(.inset)
                }
            }
            .frame(minWidth: 380)
        }
    }

    func loadAllJobs() {
        loadingJobs = true
        loadError = nil
        let companies = state.watchlist
        Task {
            let source = CompanyWatchlistSource(companies: companies)
            do {
                var query = SearchQuery()
                query.limit = 1000
                var jobs = try await source.search(query)
                jobs.sort { ($0.posted ?? .distantPast) > ($1.posted ?? .distantPast) }
                await MainActor.run {
                    companyJobs = jobs
                    loadingJobs = false
                }
            } catch {
                await MainActor.run {
                    loadError = "Failed: \(error.localizedDescription)"
                    loadingJobs = false
                }
            }
        }
    }
}

struct AddCompanySheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) var dismiss

    @State private var input = ""
    @State private var detecting = false
    @State private var detected: ATSCompany?
    @State private var jobCount = 0
    @State private var failed = false
    @State private var manualKind: ATSKind = .personio
    @State private var manualSlug = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add a company").font(.title3.weight(.semibold))

            Text("Enter the company name or paste its careers-page URL — JobScout tries the public job feeds of Personio, Greenhouse, Lever, Recruitee and SmartRecruiters.")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                TextField("e.g. “gitlab” or https://acme.jobs.personio.de", text: $input)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { detect() }
                Button {
                    detect()
                } label: {
                    if detecting {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Detect")
                    }
                }
                .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || detecting)
            }

            if let c = detected {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("\(c.name) uses \(c.ats.label)")
                    Text("· \(jobCount) open positions").foregroundStyle(.secondary)
                }
            } else if failed {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                        Text("No supported job system found automatically.")
                    }
                    Text("If you know the system and account name, add it manually:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Picker("", selection: $manualKind) {
                            ForEach(ATSKind.allCases, id: \.self) { Text($0.label).tag($0) }
                        }
                        .fixedSize()
                        TextField("account slug", text: $manualSlug)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 160)
                        Button("Verify") { verifyManual() }
                            .disabled(manualSlug.isEmpty || detecting)
                    }
                }
            }

            Spacer()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add to watchlist") { add() }
                    .buttonStyle(.borderedProminent)
                    .disabled(detected == nil)
            }
        }
        .padding(20)
        .frame(width: 480, height: 300)
    }

    func detect() {
        detecting = true
        detected = nil
        failed = false
        let query = input.trimmingCharacters(in: .whitespaces)
        Task {
            let result = await ATSDetector.detect(companyNameOrURL: query)
            var count = 0
            if let r = result {
                count = (try? await ATSClient.fetchJobs(for: r).count) ?? 0
            }
            await MainActor.run {
                detected = result
                jobCount = count
                failed = result == nil
                detecting = false
            }
        }
    }

    func verifyManual() {
        detecting = true
        var candidate = ATSCompany(
            name: input.trimmingCharacters(in: .whitespaces),
            ats: manualKind,
            slug: manualSlug.trimmingCharacters(in: .whitespaces).lowercased()
        )
        if manualKind == .personio {
            candidate.host = "\(candidate.slug).jobs.personio.de"
        }
        Task {
            let jobs = (try? await ATSClient.fetchJobs(for: candidate)) ?? []
            await MainActor.run {
                if jobs.isEmpty {
                    failed = true
                    detected = nil
                } else {
                    detected = candidate
                    jobCount = jobs.count
                    failed = false
                }
                detecting = false
            }
        }
    }

    func add() {
        guard var c = detected else { return }
        // Prefer a human name over a slug when the user typed a name.
        let typed = input.trimmingCharacters(in: .whitespaces)
        if !typed.contains("http"), !typed.contains("."), !typed.isEmpty {
            c.name = typed
        }
        if !state.watchlist.contains(where: { $0.id == c.id }) {
            state.watchlist.append(c)
        }
        dismiss()
    }
}
