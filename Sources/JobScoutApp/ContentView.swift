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
                        if item == .saved && !state.favorites.isEmpty {
                            Text("\(state.favorites.count)")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.secondary.opacity(0.2)))
                        }
                        if item == .companies && !state.watchlist.isEmpty {
                            Text("\(state.watchlist.count)")
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
            case .companies: WatchlistView()
            case .saved: SavedView()
            }
        }
        .navigationTitle("JobScout")
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

struct JobRow: View {
    @EnvironmentObject var state: AppState
    let job: Job

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .top) {
                Text(job.title)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                Spacer(minLength: 8)
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
            Button(state.isFavorite(job) ? "Remove from Saved" : "Save Job") {
                state.toggleFavorite(job)
            }
        }
    }
}

struct JobDetailView: View {
    @EnvironmentObject var state: AppState
    let job: Job

    var body: some View {
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
                        Text(job.detectedLanguage == "de" ? "German 🇩🇪" : "English 🇬🇧")
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

                if !job.descriptionText.isEmpty {
                    Divider()
                    Text("Description").font(.headline)
                    Text(job.descriptionText)
                        .font(.callout)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("Open the job in your browser for the full description.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}
