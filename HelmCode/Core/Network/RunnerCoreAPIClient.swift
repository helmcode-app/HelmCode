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

    func setupStatus() async throws -> SetupPublicStatus {
        try await get(path: "/v1/setup", authorize: false)
    }

    func enrollDevice(code: String, deviceName: String) async throws -> SetupEnrollResponse {
        try await post(
            path: "/v1/setup/enroll",
            body: SetupEnrollBody(code: code, deviceName: deviceName),
            expectedStatus: 200,
            authorize: false
        )
    }

    func pollEnrollment(id: String) async throws -> SetupEnrollResponse {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        return try await get(
            path: "/v1/setup/enrollments/\(encoded)",
            authorize: false
        )
    }

    func startDeviceInvite(url: String) async throws -> SetupPairTicket {
        try await post(
            path: "/v1/setup/invites",
            body: SetupInviteBody(url: url),
            expectedStatus: 200
        )
    }

    func listDevices() async throws -> SetupDevicesResponse {
        try await get(path: "/v1/setup/devices", authorize: true)
    }

    func listPendingEnrollments() async throws -> SetupEnrollmentsResponse {
        try await get(path: "/v1/setup/enrollments", authorize: true)
    }

    func approveEnrollment(id: String) async throws {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let _: OkResponse = try await postEmpty(
            path: "/v1/setup/enrollments/\(encoded)/approve",
            expectedStatus: 200
        )
    }

    func denyEnrollment(id: String) async throws {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let _: OkResponse = try await postEmpty(
            path: "/v1/setup/enrollments/\(encoded)/deny",
            expectedStatus: 200
        )
    }

    func revokeDevice(id: String) async throws {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let _: OkResponse = try await perform(
            try makeRequest(
                path: "/v1/setup/devices/\(encoded)",
                method: "DELETE",
                authorize: true
            ),
            expectedStatus: 200
        )
    }

    func createWsTicket() async throws -> WsTicketResponse {
        try await postEmpty(path: "/v1/setup/ws-tickets", expectedStatus: 200)
    }

    func status() async throws -> RuntimeStatus {
        try await get(path: "/v1/status", authorize: true)
    }

    func setupSession() async throws -> SetupSessionStatus {
        try await get(path: "/v1/setup/session", authorize: true)
    }

    func startGithub() async throws -> GithubDeviceStart {
        try await postEmpty(path: "/v1/setup/github/start", expectedStatus: 200)
    }

    func pollGithub() async throws -> GithubPollResponse {
        try await get(path: "/v1/setup/github/poll", authorize: true)
    }

    func listGithubRepos() async throws -> [GithubRepoRecord] {
        let envelope: GithubReposResponse = try await get(
            path: "/v1/setup/github/repos",
            authorize: true
        )
        return envelope.repos
    }

    func cloneGithubRepo(owner: String, repo: String) async throws -> SetupSessionStatus {
        try await post(
            path: "/v1/setup/github/clone",
            body: GithubCloneBody(owner: owner, repo: repo),
            expectedStatus: 200,
            timeoutInterval: 300
        )
    }

    // MARK: - Agent sessions (`/v1/sessions/*`)

    func sessionsHealth() async throws -> SessionsRuntimeHealth {
        try await get(path: "/v1/sessions/health", authorize: true)
    }

    func sessionModels(forceRefresh: Bool = false) async throws -> SessionModelsResponse {
        let path = forceRefresh ? "/v1/sessions/models?refresh=1" : "/v1/sessions/models"
        return try await get(path: path, authorize: true)
    }

    func listWorkspaces() async throws -> ListWorkspacesEnvelope {
        try await get(path: "/v1/workspaces", authorize: true)
    }

    func createSession(
        title: String? = nil,
        workspaceId: String = HelmWorkspace.defaultID
    ) async throws -> AgentSessionDTO {
        let body = CreateSessionBody(title: title, workspaceId: workspaceId)
        let envelope: CreateSessionEnvelope = try await post(
            path: "/v1/sessions",
            body: body,
            expectedStatus: 201
        )
        return envelope.session
    }

    func listSessions() async throws -> [AgentSessionDTO] {
        let envelope: ListSessionsEnvelope = try await get(
            path: "/v1/sessions",
            authorize: true
        )
        return envelope.sessions
    }

    func getSession(id: String) async throws -> AgentSessionDTO {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let envelope: GetSessionEnvelope = try await get(
            path: "/v1/sessions/\(encoded)",
            authorize: true
        )
        return envelope.session
    }

    func promptSession(id: String, body: SessionPromptBody) async throws -> SessionPromptAccepted {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        return try await post(
            path: "/v1/sessions/\(encoded)/prompt",
            body: body,
            expectedStatus: 202
        )
    }

    func sessionHistory(id: String, limit: Int? = 200) async throws -> SessionHistoryEnvelope {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        var path = "/v1/sessions/\(encoded)/history"
        if let limit {
            path += "?limit=\(limit)"
        }
        return try await get(path: path, authorize: true)
    }

    func cancelSession(id: String) async throws -> SessionCancelResponse {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        return try await postEmpty(
            path: "/v1/sessions/\(encoded)/cancel",
            expectedStatus: 200
        )
    }

    func rewindSession(
        id: String,
        messageId: String,
        restore: SessionRewindRestore = .both
    ) async throws -> SessionRewindResponse {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        return try await post(
            path: "/v1/sessions/\(encoded)/rewind",
            body: SessionRewindBody(messageId: messageId, restore: restore),
            expectedStatus: 200
        )
    }

    func deleteSession(id: String) async throws -> SessionDeleteResponse {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        return try await perform(
            try makeRequest(path: "/v1/sessions/\(encoded)", method: "DELETE", authorize: true),
            expectedStatus: 200
        )
    }

    // MARK: - HTTP

    private func get<T: Decodable>(path: String, authorize: Bool) async throws -> T {
        try await perform(try makeRequest(path: path, method: "GET", authorize: authorize))
    }

    private func post<T: Decodable, B: Encodable>(
        path: String,
        body: B,
        expectedStatus: Int,
        authorize: Bool = true,
        timeoutInterval: TimeInterval = 0
    ) async throws -> T {
        let data = try encoder.encode(body)
        let request = try makeRequest(
            path: path,
            method: "POST",
            authorize: authorize,
            bodyData: data,
            timeoutInterval: timeoutInterval
        )
        return try await perform(request, expectedStatus: expectedStatus)
    }

    private struct OkResponse: Decodable {
        let ok: Bool?
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
        bodyData: Data? = nil,
        timeoutInterval: TimeInterval = 0
    ) throws -> URLRequest {
        let root = try baseURL()
        guard let url = URL(string: path, relativeTo: root)?.absoluteURL else {
            throw HelmNetworkError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.timeoutInterval = timeoutInterval > 0 ? timeoutInterval : (method == "POST" ? 60 : 15)

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
