# JobScout — free multi-platform job search for macOS (Apple Silicon)

A **native SwiftUI Mac app** that searches jobs across five platforms **and
directly from company career pages** — merged, de-duplicated, filtered. All
sources are free public endpoints: **no paid APIs, no login, no keys to buy.**

```
┌────────────────────────────────────────────────────────────┐
│  Search   [Koch, Kellner        ] [Berlin  ] (🔍 Search)   │
│  Posted ▾  Language ▾  Job type ▾  Experience ▾  Radius ▾  │
│  Sources: ☑ LinkedIn ☑ Arbeitsagentur ☑ Indeed ☑ Xing …    │
│  ┌──────────────────────────────┬───────────────────────┐  │
│  │ Koch (m/w/d) — Hopfingerbräu │  Job detail, salary,  │  │
│  │ Kellner — L'Osteria  ⭐      │  posted date, links,  │  │
│  │ …                            │  open in browser      │  │
│  └──────────────────────────────┴───────────────────────┘  │
└────────────────────────────────────────────────────────────┘
```

## Sources & how each one works

| Source | Technique | Status |
|---|---|---|
| **Arbeitsagentur** | Official public REST API v6 (the same one jobsuche.arbeitsagentur.de uses; `X-API-Key: jobboerse-jobsuche` is that site's own public client id) | ✅ most reliable |
| **LinkedIn** | Public guest jobs endpoint (no login) — ported from the proven `job-platform` Python adapter | ✅ |
| **Indeed** | The Indeed mobile app's GraphQL API with its public embedded key (JobSpy technique) | ✅ works today; Indeed may rotate the key someday |
| **Xing** | Server-rendered public search results, parsed from HTML | ✅ |
| **StepStone** | Server-rendered results with stable `data-at` attributes | ✅ works today; occasionally bot-blocked → shows honest ⚠️ |
| **Company career pages** | Watchlist: auto-detects a company's ATS — **Personio, Greenhouse, Lever, Recruitee, SmartRecruiters** — and reads its public jobs feed (JSON/XML) | ✅ |
| ~~Jobruf~~ | Investigated and excluded: it is a registration-only student-gig placement service with **no public job listings** to search | ❌ not possible |

Failures are never silent: a source that errors shows an orange ⚠️ with the
reason, and the rest keep working.

## Filters

- **Date posted** — any / 24 h / week / month (native on LinkedIn, Arbeitsagentur,
  Indeed, Xing; StepStone & career pages filter by parsed posting dates)
- **Language** — German / English, auto-detected from the posting (umlauts,
  "(m/w/d)"-style markers, German job vocabulary + Apple's NaturalLanguage)
- **Job title / keywords** — comma-separated terms run as parallel searches and
  merge fairly (round-robin) before de-duplication
- **Experience** — Entry/Junior · Mid · Senior/Lead (native on LinkedIn,
  conservative title-based filter elsewhere — ambiguous titles always pass)
- **Job type** — full-time, part-time, contract, temporary, internship, minijob
- **Workplace** — on-site / remote / hybrid · **Location + radius (km)**
- Per-source enable/disable · results limit per source

Plus: ⭐ saved jobs, company watchlist, **CSV/JSON export**, open-in-browser,
copy link — all persisted in `~/Library/Application Support/JobScout/`.

## Build & run

Requires only Xcode **Command Line Tools** (no full Xcode) on Apple Silicon:

```bash
cd jobscout-app
./build-app.sh          # builds release binary + assembles JobScout.app
open JobScout.app
```

Dev loop: `swift build` and `swift run JobScout`.

### CLI (same engine, for scripting/testing)

```bash
swift build
./.build/debug/jobscout-cli search --keywords "Koch" --location Berlin \
    --sources linkedin,arbeitsagentur,indeed,xing,stepstone \
    --date week --types part-time --lang de --limit 10 [--json]

./.build/debug/jobscout-cli detect-ats "gitlab"        # which ATS a company uses
./.build/debug/jobscout-cli company-jobs --ats greenhouse --slug gitlab
```

## Project layout

```
jobscout-app/
├── Package.swift                  # SwiftPM, only dependency: SwiftSoup
├── build-app.sh                   # release build → JobScout.app (+icon, ad-hoc sign)
├── Sources/
│   ├── JobScoutCore/              # engine (UI-independent)
│   │   ├── Models.swift           # Job, SearchQuery, filter enums, JobSource protocol
│   │   ├── Aggregator.swift       # concurrent fan-out, round-robin merge, de-dup
│   │   ├── Language.swift         # DE/EN detection + experience post-filter
│   │   ├── HTTP.swift             # shared session, date parsing (incl. "vor 3 Tagen")
│   │   ├── SourceRegistry.swift
│   │   └── Sources/               # one file per platform
│   │       ├── LinkedInSource.swift
│   │       ├── ArbeitsagenturSource.swift
│   │       ├── IndeedSource.swift
│   │       ├── XingSource.swift
│   │       ├── StepStoneSource.swift
│   │       └── ATSSources.swift   # 5 ATS clients + detector + watchlist source
│   ├── JobScoutApp/               # SwiftUI app (sidebar: Search / Companies / Saved)
│   └── JobScoutCLI/               # jobscout-cli test harness
└── scripts/                       # Info.plist, icon generator
```

**Adding a platform** = one file implementing `JobSource` (`name` +
`search(_:) async throws -> [Job]`), then one line in `SourceRegistry`.

## Honest limitations

- Scrapers (everything except Arbeitsagentur and the ATS feeds) depend on the
  sites' current HTML/API shapes — they can break without notice and need a
  small fix when they do. Verified working **2026-07-25**.
- Indeed/Glassdoor experience filters aren't native; the title-heuristic filter
  is conservative on purpose. Glassdoor itself was skipped (aggressive bot
  protection + rotating tokens; Indeed covers the same aggregator space).
- Be polite: the app rate-limits itself (delays between pages, capped paging).
  Intended for **personal job searching**, not mass harvesting; heavy use can
  get your IP temporarily blocked by individual sites.
