# JobScout — English-speaking job search + application tracker for macOS

A **native SwiftUI Mac app** for finding **English-speaking jobs** across a
whole country, on five platforms **and directly from company career pages**
(merged, de-duplicated, filtered), and for **tracking every application** in
an Excel sheet that updates itself. All sources are free public endpoints:
**no paid APIs, no login, no keys to buy.**

```
┌────────────────────────────────────────────────────────────────────┐
│  Search  [data analyst, BI developer   ] [🇩🇪 Germany ▾] (Search)  │
│  Posted ▾ Job type ▾ Experience ▾ Workplace ▾ ☑ English only ☐ Hide applied │
│  Sources: ☑ LinkedIn ☑ Indeed ☑ Arbeitsagentur ☑ Xing ☑ StepStone │
│  🇩🇪 Germany · Confirming English postings 120/180 · 65 hidden     │
│  ┌───────────────────────────────────┬──────────────────────────┐  │
│  │ Data Analyst (m/f/d) — Ablefy  ✈︎ ☆│ Full description, German │  │
│  │ ✓ Applied 20 Oct · Interview      │ requirement, Mark as     │  │
│  │ Senior Data Analyst  German a plus│ Applied / status pickers │  │
│  └───────────────────────────────────┴──────────────────────────┘  │
└────────────────────────────────────────────────────────────────────┘
```

## Searching a country

There is no city and no radius: pick a **country** and every source searches
all of it. LinkedIn, Indeed and company career sites work in all 26 listed
countries (Germany, Austria, Switzerland, Netherlands, UK, Ireland, US, …);
the German boards only run where they have jobs: Arbeitsagentur and StepStone
in Germany, Xing in Germany/Austria/Switzerland. Unavailable sources are
greyed out with a tooltip. Results per source and keyword default to **100**
(up to 500 in Settings), and the merged list is no longer capped, so a
five-source search returns several hundred jobs.

## English-speaking jobs only

**English postings only** is on by default:

1. **Indeed** filters natively with its own per-job language tag.
2. Titles with clear German words (*Mitarbeiter, Koch, für, Vollzeit* …) are
   dropped straight away. "(m/w/d)" alone doesn't count, since English ads in
   Germany use it too.
3. Every remaining posting is **confirmed from its full description** in the
   background (a few at a time per site, with pauses). Postings that turn out
   to be in German, Dutch, French … disappear as they're found. A site that
   starts rate-limiting is left alone, and its jobs keep their title verdict.
4. For English postings the description is also scanned for German
   requirements, shown as **German required** or **German a plus** tags
   (benefits like "free German courses" are ignored).

The confirmation step can be switched off in Settings to save time and data.

## Tracking applications (Excel)

- Click **✈︎** on a result, use **Mark as Applied** in the detail pane, or
  ⌘/⇧-click several results and mark them all in one go.
- Each application is saved with a snapshot of the posting **including its
  complete description** (fetched automatically if the site didn't send it).
- Set **Status** (Applied → Followed up → Phone screen → Interview →
  Assessment → Final interview) and **Decision** (Awaiting, Offer received,
  Offer accepted/declined, Rejected, Withdrawn, No response) **in the app**,
  in the Applications tab or straight from a search result. Add notes; every
  change is logged in a history.
- JobScout rewrites **`~/Documents/JobScout/Job Applications.xlsx`** (location
  changeable) about a second after any change: one row per application with
  dates, status, decision, notes, status history, link and full description,
  plus a Summary sheet. The sheet is a mirror. Edit statuses in the app, not in
  Excel (if the file is open in Excel, reopen it to see the latest version).
- Future searches recognise jobs you already applied to, even when the same ad
  shows up on another site, and badge them **✓ Applied 20 Oct · Interview**.
  **Hide jobs I applied to** removes them from results.

## Sources & how each one works

| Source | Technique | Status |
|---|---|---|
| **Arbeitsagentur** | Official public REST API v6 (the same one jobsuche.arbeitsagentur.de uses; `X-API-Key: jobboerse-jobsuche` is that site's own public client id). Descriptions: v4 `jobdetails/{base64 refnr}` | ✅ most reliable · Germany only |
| **LinkedIn** | Public guest jobs endpoint (no login), `location=<country name>`. Descriptions: guest `jobPosting/{id}` | ✅ |
| **Indeed** | The Indeed mobile app's GraphQL API with its public embedded key (JobSpy technique); country via `indeed-co`, native `language: en` filter, descriptions included | ✅ works today; Indeed may rotate the key someday |
| **Xing** | Server-rendered public search results, parsed from HTML. Since 2026-10 Xing's AI search ignores the location, so jobs are placed into the country from their location text. Descriptions: JSON-LD `JobPosting` | ✅ DE/AT/CH |
| **StepStone** | Server-rendered results with stable `data-at` attributes. Descriptions: JSON-LD `JobPosting` | ✅ Germany only; occasionally bot-blocked → shows honest ⚠️ |
| **Company career pages** | Watchlist: auto-detects a company's ATS — **Personio, Greenhouse, Lever, Recruitee, SmartRecruiters** — and reads its public jobs feed (JSON/XML) with descriptions; filtered to the selected country | ✅ |
| ~~Jobruf~~ | Investigated and excluded: it is a registration-only student-gig placement service with **no public job listings** to search | ❌ not possible |

Failures are never silent: a source that errors shows an orange ⚠️ with the
reason, and the rest keep working.

## Filters

- **Country** (whole country, no city/radius) · **English postings only**
- **Date posted**: any / 24 h / week / month (native on LinkedIn, Arbeitsagentur,
  Xing; Indeed, StepStone & career pages filter by exact posting dates)
- **Job title / keywords**: comma-separated terms run as parallel searches and
  merge fairly (round-robin) before de-duplication (company + title + city,
  so the same ad on two sites shows once)
- **Experience**: Entry/Junior · Mid · Senior/Lead (native on LinkedIn,
  conservative title-based filter elsewhere; ambiguous titles always pass)
- **Job type**: full-time, part-time, contract, temporary, internship, minijob
- **Workplace**: on-site / remote / hybrid · **Hide jobs I applied to**
- Per-source enable/disable · results per source (Settings)

Plus: ⭐ saved jobs, company watchlist, **CSV/JSON export** (with applied
status), open-in-browser, copy link. Data lives in
`~/Library/Application Support/JobScout/` (`applications.json` is the
tracker's source of truth).

## Build & run

Requires only Xcode **Command Line Tools** (no full Xcode) on Apple Silicon:

```bash
cd jobscout-app
./build-app.sh          # builds release binary + assembles JobScout.app
open JobScout.app
```

Dev loop: `swift build` and `swift run JobScout`. Tests: `./test.sh` (Swift
Testing; the script adds the flags Command Line Tools need).

### CLI (same engine, for scripting/testing)

```bash
swift build
./.build/debug/jobscout-cli search --keywords "data analyst" --country DE \
    --sources linkedin,arbeitsagentur,indeed,xing,stepstone \
    --date week --types full-time --limit 100 [--any-language] [--details 5] [--json]

./.build/debug/jobscout-cli countries                  # countries + which boards work there
./.build/debug/jobscout-cli export-applications --out ~/Desktop/applications.xlsx
./.build/debug/jobscout-cli detect-ats "gitlab"        # which ATS a company uses
./.build/debug/jobscout-cli company-jobs --ats greenhouse --slug gitlab
```

`--details N` fetches the full description of the first N results and prints
its language and German requirement, a quick way to check every source.

## Project layout

```
jobscout-app/
├── Package.swift                  # SwiftPM, only dependency: SwiftSoup
├── build-app.sh                   # release build → JobScout.app (+icon, ad-hoc sign)
├── Sources/
│   ├── JobScoutCore/              # engine (UI-independent)
│   │   ├── Models.swift           # Job, SearchQuery, filter enums, JobSource protocol
│   │   ├── Country.swift          # 26 countries, location → country placement
│   │   ├── Aggregator.swift       # concurrent fan-out, round-robin merge, de-dup
│   │   ├── Language.swift         # English detection, German-requirement scan, experience filter
│   │   ├── Details.swift          # full descriptions per source + HTML → text
│   │   ├── Tracker.swift          # applications, statuses, ApplicationBook, workbook layout
│   │   ├── XLSX.swift             # dependency-free .xlsx writer (zip + deflate)
│   │   ├── HTTP.swift             # shared session, date parsing (incl. "vor 3 Tagen")
│   │   ├── SourceRegistry.swift
│   │   └── Sources/               # one file per platform
│   │       ├── LinkedInSource.swift
│   │       ├── ArbeitsagenturSource.swift
│   │       ├── IndeedSource.swift
│   │       ├── XingSource.swift
│   │       ├── StepStoneSource.swift
│   │       └── ATSSources.swift   # 5 ATS clients + detector + watchlist source
│   ├── JobScoutApp/               # SwiftUI app (Search / Applications / Companies / Saved)
│   └── JobScoutCLI/               # jobscout-cli test harness
├── Tests/JobScoutCoreTests/       # Swift Testing suite (./test.sh)
└── scripts/                       # Info.plist, icon generator
```

**Adding a platform** = one file implementing `JobSource` (`name` +
`search(_:) async throws -> [Job]`), then one line in `SourceRegistry`.

## Honest limitations

- Scrapers (everything except Arbeitsagentur and the ATS feeds) depend on the
  sites' current HTML/API shapes — they can break without notice and need a
  small fix when they do. Verified working **2026-10-23**.
- Indeed/Glassdoor experience filters aren't native; the title-heuristic filter
  is conservative on purpose. Glassdoor itself was skipped (aggressive bot
  protection + rotating tokens; Indeed covers the same aggregator space).
- The English check reads one page per posting. It runs a few requests at a
  time per site with pauses, and stops for a site that starts refusing.
- Be polite: the app rate-limits itself (delays between pages, capped paging).
  Intended for **personal job searching**, not mass harvesting; heavy use can
  get your IP temporarily blocked by individual sites.
