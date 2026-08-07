import Foundation

/// Runs multiple sources (and keywords) concurrently, merges and de-duplicates.
///
/// Results are interleaved round-robin so every keyword/source contributes
/// fairly, then de-duplicated across all of them. One failing search never
/// breaks the others; failures surface per source in `SourceStatus`.
public enum Aggregator {
    public static func run(
        queries: [SearchQuery], sources: [any JobSource]
    ) async -> SearchResult {
        struct PairResult {
            let source: String
            let index: Int
            let jobs: [Job]
            let error: String?
        }

        let pairs: [(index: Int, source: any JobSource, query: SearchQuery)] =
            queries.flatMap { query in
                sources.map { (0, $0, query) }
            }.enumerated().map { (i, t) in (i, t.1, t.2) }

        let results = await withTaskGroup(of: PairResult.self) { group in
            for pair in pairs {
                group.addTask {
                    do {
                        let jobs = try await pair.source.search(pair.query)
                        return PairResult(
                            source: pair.source.name, index: pair.index,
                            jobs: jobs, error: nil)
                    } catch {
                        let msg = (error as? HTTPError)?.description
                            ?? (error as? SourceError)?.message
                            ?? error.localizedDescription
                        return PairResult(
                            source: pair.source.name, index: pair.index,
                            jobs: [], error: msg)
                    }
                }
            }
            var all: [PairResult] = []
            for await r in group { all.append(r) }
            return all.sorted { $0.index < $1.index }
        }

        // Per-source status (merge multi-keyword runs of the same source).
        var counts: [String: Int] = [:]
        var errors: [String: String] = [:]
        for r in results {
            counts[r.source, default: 0] += r.jobs.count
            if let e = r.error { errors[r.source] = e }
        }
        let statuses = sources.map {
            SourceStatus(source: $0.name, count: counts[$0.name] ?? 0, error: errors[$0.name])
        }

        // Round-robin interleave + de-dup.
        var merged: [Job] = []
        var seen = Set<String>()
        let lists = results.map(\.jobs)
        let maxLen = lists.map(\.count).max() ?? 0
        for i in 0..<maxLen {
            for list in lists where i < list.count {
                let job = list[i]
                let key = job.dedupKey()
                if seen.insert(key).inserted {
                    merged.append(job)
                }
            }
        }

        // Generic post-filters (sources apply native filters where they can).
        if let query = queries.first {
            merged = LanguageDetector.filter(merged, languages: query.languages)
            merged = ExperienceFilter.apply(merged, wanted: query.experience)
            if let cutoff = query.datePosted.cutoff {
                // Only drop jobs we positively know are older; unknown dates pass
                // (their source already filtered natively where supported).
                merged = merged.filter { job in
                    guard let posted = job.posted else { return true }
                    return posted >= cutoff
                }
            }
            let totalLimit = query.limit * max(queries.count, 1)
            if merged.count > totalLimit {
                merged = Array(merged.prefix(totalLimit))
            }
        }

        return SearchResult(jobs: merged, statuses: statuses)
    }
}

public struct SourceError: Error {
    public let message: String
    public init(_ message: String) { self.message = message }
}
