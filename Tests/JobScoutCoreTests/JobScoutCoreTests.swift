import Foundation
import Testing
@testable import JobScoutCore

// MARK: - Helpers

private func job(
    _ title: String, company: String = "Acme GmbH", location: String = "Berlin",
    source: String = "linkedin", id: String = "1", description: String = ""
) -> Job {
    Job(source: source, jobID: id, title: title, company: company, location: location,
        url: "https://example.com/jobs/\(id)", descriptionText: description)
}

/// Runs /usr/bin/unzip and returns stdout (the archive tool is part of macOS).
private func unzip(_ args: [String]) throws -> (status: Int32, out: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe
    try p.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus, String(decoding: data, as: UTF8.self))
}

private func isWellFormedXML(_ xml: String) -> Bool {
    XMLParser(data: Data(xml.utf8)).parse()
}

// MARK: - Language

@Suite struct LanguageTests {
    @Test func germanTitlesAreRecognised() {
        #expect(LanguageDetector.titleVerdict("Mitarbeiter Kundenservice (m/w/d)") == .notEnglish)
        #expect(LanguageDetector.titleVerdict("Koch für unser Restaurant") == .notEnglish)
        #expect(LanguageDetector.titleVerdict("Vertriebsmitarbeiterin Innendienst") == .notEnglish)
        #expect(LanguageDetector.titleVerdict("Kellnerin in Teilzeit") == .notEnglish)
    }

    @Test func englishTitlesStayUnverifiedEvenWithGenderMarkers() {
        // English ads in Germany carry (m/w/d) and (m/f/d) too.
        #expect(LanguageDetector.titleVerdict("Software Engineer (m/w/d)") == .unverified)
        #expect(LanguageDetector.titleVerdict("Data Analyst (m/f/d)") == .unverified)
        #expect(LanguageDetector.titleVerdict("Senior Backend Engineer (all genders)") == .unverified)
    }

    @Test func descriptionDecidesOverTitle() {
        let german = String(repeating: "Wir suchen ab sofort eine engagierte Persönlichkeit für unser Team in Berlin. Ihre Aufgaben umfassen die Analyse von Daten. ", count: 3)
        let english = String(repeating: "We are looking for a motivated analyst to join our growing team in Berlin. You will analyse product data. ", count: 3)
        #expect(LanguageDetector.verdict(for: job("Data Analyst (m/w/d)", description: german)) == .notEnglish)
        #expect(LanguageDetector.verdict(for: job("Data Analyst (m/w/d)", description: english)) == .english)
    }

    @Test func otherLanguagesAreNotEnglishEither() {
        let dutch = String(repeating: "Wij zoeken een gemotiveerde data-analist voor ons team in Utrecht. Je werkt met grote hoeveelheden gegevens. ", count: 3)
        #expect(LanguageDetector.verdict(for: job("Data-analist", description: dutch)) == .notEnglish)
        var nl = job("Data Analyst")
        nl.languageHint = "nl"
        #expect(LanguageDetector.verdict(for: nl) == .notEnglish)
    }

    @Test func sourceHintWins() {
        var j = job("Kellner/Waiter (m/w/d)")
        j.languageHint = "en"
        #expect(LanguageDetector.verdict(for: j) == .english)
    }

    @Test func englishOnlyKeepsUnverifiedAndDropsGerman() {
        let jobs = [job("Software Engineer"), job("Mitarbeiter Lager (m/w/d)", id: "2")]
        #expect(LanguageDetector.englishOrUnverified(jobs).map(\.jobID) == ["1"])
    }
}

@Suite struct GermanRequirementTests {
    @Test func detectsRequirement() {
        let (r, snippet) = GermanRequirement.detect(in: "You bring 3 years of SQL. Fluent German and English (C1) are required.")
        #expect(r == .required)
        #expect(snippet?.contains("Fluent German") == true)
    }

    @Test func detectsPlusInSeparateSentence() {
        let text = "Fluent English is a must; German is a plus. You love data."
        #expect(GermanRequirement.detect(in: text).0 == .plus)
    }

    @Test func coursesAreNotRequirements() {
        let text = "Benefits: In-house German and English courses with a native speaker, 50% covered."
        #expect(GermanRequirement.detect(in: text).0 == .notMentioned)
    }

    @Test func germanyIsNotGerman() {
        #expect(GermanRequirement.detect(in: "Our office is in Germany. Strong SQL skills are required.").0 == .notMentioned)
    }

    @Test func germanPhrasingInsideEnglishAd() {
        #expect(GermanRequirement.detect(in: "Requirements:\n• Sehr gute Deutschkenntnisse").0 == .required)
    }
}

// MARK: - Countries

@Suite struct CountryTests {
    let de = Country.germany

    @Test func placesLocations() {
        #expect(Countries.place("München, Bayern, Deutschland", in: de) == .inCountry)
        #expect(Countries.place("Berlin, Berlin, Germany", in: de) == .inCountry)
        #expect(Countries.place("10117 Berlin", in: de) == .inCountry)
        #expect(Countries.place("London, UK", in: de) == .elsewhere)
        #expect(Countries.place("Zürich", in: de) == .elsewhere)
        #expect(Countries.place("Austin, TX, US", in: de) == .elsewhere)
        #expect(Countries.place("Remote", in: de) == .unknown)
        #expect(Countries.place("", in: de) == .unknown)
    }

    @Test func findsByCodeAndName() {
        #expect(Countries.find("de")?.name == "Germany")
        #expect(Countries.find("United Kingdom")?.code == "GB")
        #expect(Countries.find("Österreich")?.code == "AT")
    }

    @Test func availability() {
        let uk = Countries.byCode["GB"]!
        #expect(SourceRegistry.isAvailable("arbeitsagentur", in: de))
        #expect(!SourceRegistry.isAvailable("arbeitsagentur", in: uk))
        #expect(!SourceRegistry.isAvailable("stepstone", in: uk))
        #expect(SourceRegistry.isAvailable("linkedin", in: uk))
        #expect(SourceRegistry.isAvailable("xing", in: Countries.byCode["CH"]!))
    }
}

// MARK: - Tracking & dedup

@Suite struct TrackingTests {
    @Test func trackingKeyIgnoresGenderMarkersAndLegalForm() {
        let a = job("Software Engineer (m/w/d)", company: "Acme GmbH")
        let b = job("Software Engineer (all genders)", company: "ACME", source: "indeed", id: "x")
        let c = job("Software Engineer m/f/d", company: "Acme SE", source: "xing", id: "y")
        #expect(a.trackingKey == b.trackingKey)
        #expect(a.trackingKey == c.trackingKey)
        #expect(a.trackingKey != job("Data Engineer", company: "Acme").trackingKey)
    }

    @Test func dedupAcrossLocationFormats() {
        let a = job("Data Analyst (m/w/d)", location: "Berlin, Berlin, Germany")
        let b = job("Data Analyst (m/w/d)", location: "10117 Berlin", source: "indeed", id: "2")
        let c = job("Data Analyst (m/w/d)", location: "Hamburg", source: "indeed", id: "3")
        #expect(a.dedupKey() == b.dedupKey())
        #expect(a.dedupKey() != c.dedupKey())
    }

    @Test func applicationRecordsHistory() {
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        var app = TrackedApplication(job: job("Data Analyst"), country: "Germany", appliedOn: start)
        #expect(app.stage == .applied)
        #expect(app.decision == .pending)
        app.setStage(.interview, at: start.addingTimeInterval(86_400))
        app.setStage(.interview) // no-op
        app.setDecision(.rejected, at: start.addingTimeInterval(2 * 86_400))
        #expect(app.history.map(\.text) == ["Applied", "Status: Interview", "Decision: Rejected"])
        #expect(app.decisionDate == start.addingTimeInterval(2 * 86_400))
        app.setDecision(.pending)
        #expect(app.decisionDate == nil)
    }

    @Test func oldSavedJobsStillDecode() throws {
        // favorites.json written before languageHint existed.
        let json = """
        [{"source":"linkedin","jobID":"1","title":"T","company":"C","location":"L","url":"u",
          "postedDateRaw":"","remote":"","salary":"","employmentType":"","descriptionText":""}]
        """
        let jobs = try JSONDecoder().decode([Job].self, from: Data(json.utf8))
        #expect(jobs.first?.languageHint == nil)
    }
}

// MARK: - Tracker flow (what the app does on "Mark as Applied" and status changes)

@Suite struct ApplicationBookTests {
    @Test func markAppliedRecognisesTheSameJobOnAnotherSite() {
        var book = ApplicationBook()
        let linkedIn = job("Data Analyst (m/f/d)", company: "Femtasy GmbH", location: "Berlin, Berlin, Germany")
        let added = book.markApplied([linkedIn], country: "Germany", descriptions: [linkedIn.id: "Full text"])
        #expect(added == [linkedIn.id])
        #expect(book.applications.first?.job.descriptionText == "Full text")

        // A later search finds the same ad on Indeed: shown as applied, not added twice.
        let indeed = job("Data Analyst (f/d/m)", company: "Femtasy", location: "10245 Berlin", source: "indeed", id: "jk1")
        #expect(book.application(for: indeed)?.id == linkedIn.id)
        #expect(book.markApplied([indeed], country: "Germany").isEmpty)
        #expect(book.applications.count == 1)
        #expect(book.application(for: job("Data Engineer", company: "Femtasy", id: "9")) == nil)
    }

    @Test func statusChangesFlowIntoTheExcelSheet() throws {
        var book = ApplicationBook()
        let j = job("Senior Data Analyst", company: "Usercentrics", description: "About the role")
        book.markApplied([j], country: "Germany")
        func sheetXML() throws -> String {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("jobscout-flow-\(UUID().uuidString).xlsx")
            try ApplicationsWorkbook.build(book.applications).write(to: url)
            defer { try? FileManager.default.removeItem(at: url) }
            return try unzip(["-p", url.path, "xl/worksheets/sheet1.xml"]).out
        }
        let before = try sheetXML()
        #expect(before.contains("Awaiting decision"))
        #expect(before.contains("About the role"))

        book.update(j.id) { $0.setStage(.interview) }
        book.update(j.id) { $0.setDecision(.offer); $0.notes = "Offer call on Monday" }
        let after = try sheetXML()
        #expect(after.contains(">Interview<"))
        #expect(after.contains(">Offer received<"))
        #expect(after.contains("Offer call on Monday"))
        #expect(after.contains("Decision: Offer received"), "status history column")
        #expect(!after.contains("Awaiting decision"))

        book.remove(j.id)
        #expect(!(try sheetXML()).contains("Usercentrics"))
    }
}

// MARK: - HTML

@Suite struct HTMLTextTests {
    @Test func keepsParagraphsAndBullets() {
        let text = HTMLText.plain("<p><b>About</b> us</p><ul><li>SQL</li><li>Python&nbsp;3</li></ul>Line<br>break")
        #expect(text == "About us\n\n• SQL\n\n• Python 3\n\nLine\nbreak" || text == "About us\n\n• SQL\n• Python 3\n\nLine\nbreak")
    }

    @Test func unescapesEscapedHTML() {
        #expect(HTMLText.plain("&lt;p&gt;Hello &amp;amp; welcome&lt;/p&gt;").hasPrefix("Hello"))
    }

    @Test func detectsCookieNotices() {
        let consent = "Wir benötigen Ihre Einwilligung, bevor Sie unsere Website weiter besuchen können. Personenbezogene Daten können verarbeitet werden (z. B. IP-Adressen)."
        #expect(JobDetails.looksLikeCookieNotice(consent))
        #expect(!JobDetails.looksLikeCookieNotice("We are hiring a data analyst. You will build dashboards and work with privacy-conscious data."))
    }
}

// MARK: - Excel

@Suite struct XLSXTests {
    func sampleApplications() -> [TrackedApplication] {
        var a = TrackedApplication(
            job: job("Data Analyst (m/f/d)", company: "Ablefy", description: "About us\n• SQL & Python <3\u{0B}"),
            country: "Germany", appliedOn: Date(timeIntervalSince1970: 1_790_000_000))
        a.setStage(.interview)
        a.setDecision(.offer)
        a.notes = "Recruiter: Jane — \"great call\""
        let long = String(repeating: "x", count: 40_000)
        let b = TrackedApplication(job: job("Engineer", id: "2", description: long), country: "Germany")
        return [a, b]
    }

    @Test func columnNames() {
        #expect(XLSX.columnName(0) == "A")
        #expect(XLSX.columnName(25) == "Z")
        #expect(XLSX.columnName(26) == "AA")
        #expect(XLSX.columnName(17) == "R")
    }

    @Test func crc32MatchesKnownValue() {
        #expect(CRC32.checksum(Data("123456789".utf8)) == 0xCBF4_3926)
    }

    @Test func workbookIsAValidZipWithWellFormedParts() throws {
        let data = ApplicationsWorkbook.build(sampleApplications())
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("jobscout-test-\(UUID().uuidString).xlsx")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let test = try unzip(["-t", url.path])
        #expect(test.status == 0, "unzip -t failed: \(test.out)")

        let listing = try unzip(["-Z1", url.path]).out
        for part in ["[Content_Types].xml", "_rels/.rels", "xl/workbook.xml", "xl/styles.xml",
                     "xl/_rels/workbook.xml.rels", "xl/worksheets/sheet1.xml",
                     "xl/worksheets/sheet2.xml", "xl/worksheets/_rels/sheet1.xml.rels"] {
            #expect(listing.contains(part), "missing \(part)")
            // unzip treats [...] as a wildcard, so escape the brackets.
            let pattern = part.replacingOccurrences(of: "[", with: "\\[")
            let xml = try unzip(["-p", url.path, pattern]).out
            #expect(isWellFormedXML(xml), "\(part) is not well-formed XML")
        }

        let sheet = try unzip(["-p", url.path, "xl/worksheets/sheet1.xml"]).out
        #expect(sheet.contains("Ablefy"))
        #expect(sheet.contains("Offer received"))
        #expect(sheet.contains("SQL &amp; Python &lt;3"))
        #expect(!sheet.contains("\u{0B}"), "control characters must be stripped")
        #expect(sheet.contains("truncated"), "over-long descriptions are cut to Excel's cell limit")
        #expect(sheet.contains(#"<autoFilter ref="A1:R3"/>"#))
    }
}
