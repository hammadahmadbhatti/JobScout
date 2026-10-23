import SwiftUI
import JobScoutCore

struct SettingsView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Form {
            Stepper(
                "Results per source & keyword: \(state.limitPerSource)",
                value: $state.limitPerSource, in: 25...500, step: 25)
                .help("More results take longer: LinkedIn, Xing and StepStone load page by page with polite pauses.")

            Toggle("Confirm English postings from the full description", isOn: $state.verifyLanguage)
                .help("After each search, JobScout reads the description of postings whose title looks English and hides the ones written in another language. Turn off to save time and data; titles alone are then used.")

            LabeledContent("Applications sheet:") {
                VStack(alignment: .leading, spacing: 4) {
                    Text(state.excelPath.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .font(.caption)
                        .lineLimit(2)
                        .truncationMode(.middle)
                    HStack {
                        Button("Change…") { state.chooseExcelLocation() }
                        Button("Reset") { state.excelPath = AppState.defaultExcelPath }
                            .disabled(state.excelPath == AppState.defaultExcelPath)
                    }
                    .controlSize(.small)
                }
            }

            Text("All sources are free public endpoints — no API keys needed. Scraped sites can change or rate-limit at any time; failing sources show an honest ⚠️ instead of fake results.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 380)
        }
        .padding(20)
        .frame(width: 520)
    }
}
