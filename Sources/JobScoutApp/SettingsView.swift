import SwiftUI
import JobScoutCore

struct SettingsView: View {
    @EnvironmentObject var state: AppState

    static let indeedCountries = [
        ("DE", "Germany"), ("AT", "Austria"), ("CH", "Switzerland"),
        ("NL", "Netherlands"), ("FR", "France"), ("PL", "Poland"),
        ("GB", "United Kingdom"), ("US", "United States"),
    ]

    var body: some View {
        Form {
            Picker("Indeed country:", selection: state.$indeedCountry) {
                ForEach(Self.indeedCountries, id: \.0) { code, name in
                    Text(name).tag(code)
                }
            }
            .help("Which national Indeed site to search and link to")

            Stepper(
                "Results per source & keyword: \(state.limitPerSource)",
                value: $state.limitPerSource, in: 10...100, step: 10)

            Text("All sources are free public endpoints — no API keys needed. Scraped sites can change or rate-limit at any time; failing sources show an honest ⚠️ instead of fake results.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 380)
        }
        .padding(20)
        .frame(width: 460)
    }
}
