//
//  RunnerCoreAPIClient.swift
//  HelmCode
//
//  Thin URLSession client for runner-core open-core HTTP routes.
//

import Foundation

/// Stateless HTTP helper — encode/decode + auth headers only.
struct RunnerCoreAPIClient: Sendable {
    var baseURLString: String
    var apiToken: String
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(
        baseURLString: String,
        apiToken: String = "",
        session: URLSession = .shared
    ) {
        self.baseURLString = baseURLString
        self.apiToken = apiToken
        self.session = session
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.sortedKeys]
    }

    // MARK: - Routes

    func health() async throws -> HealthCheck {
        try await get(path: "/health", authorize: false)
    }

    func status() async throws -> RuntimeStatus {
        try await get(path: "/v1/status", authorize: true)
    }

    func submitTask(_ body: TaskRequest) async throws -> TaskAcceptedResponse {
        try await post(path: "/v1/tasks", body: body, expectedStatus: 202)
    }

    func pollTask(id: String) async throws -> TaskPollResponse {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        return try await get(path: "/v1/tasks/\(encoded)", authorize: true)
    }

    func cancelTask(id: String) async throws -> TaskCancelResponse {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        return try await postEmpty(path: "/v1/tasks/\(encoded)/cancel", expectedStatus: 202)
    }

    // MARK: - HTTP

    private func get<T: Decodable>(path: String, authorize: Bool) async throws -> T {
        try await perform(try makeRequest(path: path, method: "GET", authorize: authorize))
    }

    private func post<T: Decodable, B: Encodable>(
        path: String,
        body: B,
        expectedStatus: Int
    ) async throws -> T {
        let data = try encoder.encode(body)
        let request = try makeRequest(path: path, method: "POST", authorize: true, bodyData: data)
        return try await perform(request, expectedStatus: expectedStatus)
    }

    private func postEmpty<T: Decodable>(path: String, expectedStatus: Int) async throws -> T {
        try await perform(
            try makeRequest(path: path, method: "POST", authorize: true),
            expectedStatus: expectedStatus
        )
    }

    private func baseURL() throws -> URL {
        guard let url = URL(string: baseURLString), url.scheme != nil, url.host != nil else {
            throw HelmNetworkError.invalidURL
        }
        return url
    }

    private func makeRequest(
        path: String,
        method: String,
        authorize: Bool,
        bodyData: Data? = nil
    ) throws -> URLRequest {
        let root = try baseURL()
        guard let url = URL(string: path, relativeTo: root)?.absoluteURL else {
            throw HelmNetworkError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.timeoutInterval = method == "POST" ? 60 : 15

        if authorize {
            let token = apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
            if !token.isEmpty {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
        }
        if let bodyData {
            request.httpBody = bodyData
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func perform<T: Decodable>(
        _ request: URLRequest,
        expectedStatus: Int? = nil
    ) async throws -> T {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError where urlError.code == .cancelled {
            throw HelmNetworkError.cancelled
        }

        guard let http = response as? HTTPURLResponse else {
            throw HelmNetworkError.invalidResponse
        }

        if let expectedStatus, http.statusCode != expectedStatus {
            throw HelmNetworkError.http(
                http.statusCode,
                errorMessage(from: data, fallback: HTTPURLResponse.localizedString(forStatusCode: http.statusCode))
            )
        }

        if expectedStatus == nil, !(200...299).contains(http.statusCode) {
            throw HelmNetworkError.http(
                http.statusCode,
                errorMessage(from: data, fallback: HTTPURLResponse.localizedString(forStatusCode: http.statusCode))
            )
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw HelmNetworkError.decoding(error.localizedDescription)
        }
    }

    private func errorMessage(from data: Data, fallback: String) -> String {
        if let body = try? decoder.decode(APIErrorBody.self, from: data) {
            return body.error
        }
        if let raw = String(data: data, encoding: .utf8), !raw.isEmpty {
            return raw
        }
        return fallback
    }
}
