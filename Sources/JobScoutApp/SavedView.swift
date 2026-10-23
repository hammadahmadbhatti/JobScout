import SwiftUI
import JobScoutCore

struct SavedView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Group {
            if state.favorites.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "star")
                        .font(.system(size: 42))
                        .foregroundStyle(.quaternary)
                    Text("No saved jobs yet")
                        .font(.headline)
                    Text("Click the ☆ on any job to keep it here.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    List(state.favorites, selection: $state.selection) { job in
                        JobRow(job: job).tag(job.id)
                    }
                    .frame(minWidth: 400, idealWidth: 520)
                    .listStyle(.inset)

                    if let job = state.selectedJob {
                        JobDetailView(job: job)
                            .frame(minWidth: 340, idealWidth: 420)
                    } else if state.selection.count > 1 {
                        BulkSelectionView(jobs: state.selectedJobs(in: state.favorites))
                            .frame(minWidth: 340, maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        VStack {
                            Text("Select a saved job")
                                .foregroundStyle(.secondary)
                        }
                        .frame(minWidth: 340, maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Menu {
                    Button("Export CSV…") { state.export(state.favorites, format: .csv) }
                    Button("Export JSON…") { state.export(state.favorites, format: .json) }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .disabled(state.favorites.isEmpty)
            }
        }
    }
}
