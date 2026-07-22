import Foundation

struct CountResponse: Decodable {
    let total: Int
    let yourClicks: Int
    let nextClickAt: Date?
}

struct RateLimitedResponse: Decodable {
    let error: String
    let nextClickAt: Date?
}

struct HistoryPoint: Decodable, Equatable {
    let ts: Date
    let total: Int
}

enum ClickResult {
    case success(CountResponse)
    case rateLimited(nextClickAt: Date?)
}

struct APIClient {
    var baseURL = AppConfig.baseURL

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601WithFractionalSeconds
        return d
    }()

    private func request(_ path: String, method: String = "GET") -> URLRequest {
        var req = URLRequest(url: baseURL.appending(path: path))
        req.httpMethod = method
        req.setValue(ClientIdentity.id, forHTTPHeaderField: "X-Client-Id")
        req.timeoutInterval = 10
        return req
    }

    func fetchCount() async throws -> CountResponse {
        let (data, _) = try await URLSession.shared.data(for: request("/count"))
        return try Self.decoder.decode(CountResponse.self, from: data)
    }

    func click() async throws -> ClickResult {
        let (data, response) = try await URLSession.shared.data(
            for: request("/click", method: "POST"))
        if (response as? HTTPURLResponse)?.statusCode == 429 {
            let body = try Self.decoder.decode(RateLimitedResponse.self, from: data)
            return .rateLimited(nextClickAt: body.nextClickAt)
        }
        return .success(try Self.decoder.decode(CountResponse.self, from: data))
    }

    func fetchHistory() async throws -> [HistoryPoint] {
        struct Wrapper: Decodable { let history: [HistoryPoint] }
        let (data, _) = try await URLSession.shared.data(for: request("/history"))
        return try Self.decoder.decode(Wrapper.self, from: data).history
    }
}

extension JSONDecoder.DateDecodingStrategy {
    /// The server emits ISO 8601 with milliseconds ("2026-07-22T16:58:39.305Z");
    /// Foundation's stock .iso8601 rejects fractional seconds, so parse both.
    static let iso8601WithFractionalSeconds = custom { decoder in
        let s = try decoder.singleValueContainer().decode(String.self)
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = fmt.date(from: s) { return d }
        fmt.formatOptions = [.withInternetDateTime]
        if let d = fmt.date(from: s) { return d }
        throw DecodingError.dataCorrupted(.init(
            codingPath: decoder.codingPath, debugDescription: "Bad date: \(s)"))
    }
}
