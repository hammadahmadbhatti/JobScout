import Foundation

public struct HTTPError: Error, CustomStringConvertible {
    public let status: Int
    public let url: String

    public var description: String {
        switch status {
        case 403: return "HTTP 403 — the site refused this request (bot protection). Try again later."
        case 429: return "HTTP 429 — rate limited. Wait a bit and retry."
        default: return "HTTP \(status) from \(url)"
        }
    }
}

public enum HTTP {
    public static let browserUA =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
        + "(KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36"

    public static let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 25
        cfg.timeoutIntervalForResource = 60
        cfg.httpCookieAcceptPolicy = .always
        cfg.httpShouldSetCookies = true
        // English first: sites answer with English labels and dates where
        // they can ("2 days ago", "Full-time").
        cfg.httpAdditionalHeaders = ["Accept-Language": "en-US,en;q=0.9,de;q=0.6"]
        return URLSession(configuration: cfg)
    }()

    public static func get(
        _ url: URL, headers: [String: String] = [:]
    ) async throws -> Data {
        var req = URLRequest(url: url)
        req.setValue(browserUA, forHTTPHeaderField: "User-Agent")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        let (data, resp) = try await session.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            throw HTTPError(status: http.statusCode, url: url.host ?? url.absoluteString)
        }
        return data
    }

    public static func getString(
        _ url: URL, headers: [String: String] = [:]
    ) async throws -> String {
        let data = try await get(url, headers: headers)
        return String(decoding: data, as: UTF8.self)
    }

    public static func postJSON(
        _ url: URL, body: Data, headers: [String: String] = [:]
    ) async throws -> Data {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = body
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        let (data, resp) = try await session.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            throw HTTPError(status: http.statusCode, url: url.host ?? url.absoluteString)
        }
        return data
    }

    /// Build a URL from a base and query items, percent-encoding values.
    public static func url(_ base: String, _ params: [(String, String)]) -> URL {
        var comps = URLComponents(string: base)!
        comps.queryItems = params.map { URLQueryItem(name: $0.0, value: $0.1) }
        return comps.url!
    }
}

public enum DateParsing {
    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let iso: ISO8601DateFormatter = ISO8601DateFormatter()
    private static let dayOnly: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/Berlin")
        return f
    }()
    private static let localDateTime: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/Berlin")
        return f
    }()

    /// Parse the date formats seen across our sources.
    public static func parse(_ raw: String) -> Date? {
        let s = raw.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }
        if let d = isoFractional.date(from: s) { return d }
        if let d = iso.date(from: s) { return d }
        if let d = localDateTime.date(from: s) { return d }
        if let d = dayOnly.date(from: s) { return d }
        return nil
    }

    /// Parse relative strings like "vor 22 Stunden", "vor 3 Tagen", "2 days ago".
    public static func parseRelative(_ raw: String, now: Date = Date()) -> Date? {
        let s = raw.lowercased()
        guard let value = Int(s.components(separatedBy: CharacterSet.decimalDigits.inverted)
            .first(where: { !$0.isEmpty }) ?? "")
        else {
            if s.contains("gerade") || s.contains("just now") || s.contains("heute") || s.contains("today") {
                return now
            }
            return nil
        }
        let cal = Calendar.current
        if s.contains("minute") || s.contains("minuten") {
            return cal.date(byAdding: .minute, value: -value, to: now)
        }
        if s.contains("stunde") || s.contains("hour") {
            return cal.date(byAdding: .hour, value: -value, to: now)
        }
        if s.contains("tag") || s.contains("day") {
            return cal.date(byAdding: .day, value: -value, to: now)
        }
        if s.contains("woche") || s.contains("week") {
            return cal.date(byAdding: .day, value: -7 * value, to: now)
        }
        if s.contains("monat") || s.contains("month") {
            return cal.date(byAdding: .month, value: -value, to: now)
        }
        return nil
    }
}
