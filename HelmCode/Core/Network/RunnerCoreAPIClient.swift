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
            acceptedStatuses: [200]
        )
    }

    func createWsTicket() async throws -> WsTicketResponse {
        try await postEmpty(path: "/v1/setup/ws-tickets", expectedStatus: 200)
    }

    func status() async throws -> RuntimeStatus {
        try await get(path: "/v1/status", authorize: true)
    }

    // MARK: - Agent / ACP harness (`/v1/agent`)

    func agentConfig() async throws -> AgentConfigView {
        try await get(path: "/v1/agent", authorize: true)
    }

    /// Applies selection. `200` = applied; `503` = persisted but ACP failed to start.
    /// Long timeout: first enable may download Cursor / npm adapters (often 30–120s+).
    func putAgentConfig(_ body: AgentConfigUpdateBody) async throws -> AgentConfigView {
        try await put(
            path: "/v1/agent",
            body: body,
            acceptedStatuses: [200, 503],
            timeoutInterval: 600
        )
    }

    func disableAgent() async throws -> AgentConfigView {
        try await perform(
            try makeRequest(path: "/v1/agent", method: "DELETE", authorize: true),
            acceptedStatuses: [200]
        )
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

    func sessionModels(
        forceRefresh: Bool = false,
        probeModel: String? = nil
    ) async throws -> SessionModelsResponse {
        var items: [URLQueryItem] = []
        if forceRefresh { items.append(URLQueryItem(name: "refresh", value: "1")) }
        if let probeModel, !probeModel.isEmpty {
            items.append(URLQueryItem(name: "model", value: probeModel))
        }
        let path: String
        if items.isEmpty {
            path = "/v1/sessions/models"
        } else {
            var components = URLComponents()
            components.queryItems = items
            path = "/v1/sessions/models?\(components.percentEncodedQuery ?? "")"
        }
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
            acceptedStatuses: [200]
        )
    }

    /// Live SSE stream (`GET /v1/sessions/events`). Caller cancels the task to disconnect.
    func sessionEvents() -> AsyncThrowingStream<SessionStreamEventDTO, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = try makeRequest(
                        path: "/v1/sessions/events",
                        method: "GET",
                        authorize: true
                    )
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.timeoutInterval = .infinity

                    let (bytes, response) = try await session.bytes(for: request)
                    if let http = response as? HTTPURLResponse,
                       !(200...299).contains(http.statusCode) {
                        throw HelmNetworkError.http(
                            http.statusCode,
                            HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
                        )
                    }

                    var eventType = ""
                    var dataLines: [String] = []

                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        if line.isEmpty {
                            defer {
                                eventType = ""
                                dataLines = []
                            }
                            guard !dataLines.isEmpty else { continue }
                            let payload = dataLines.joined(separator: "\n")
                            guard let data = payload.data(using: .utf8) else { continue }
                            if let decoded = try? decoder.decode(SessionStreamEventDTO.self, from: data) {
                                continuation.yield(decoded)
                            } else if !eventType.isEmpty,
                                      let raw = try? decoder.decode(JSONValue.self, from: data) {
                                continuation.yield(
                                    SessionStreamEventDTO(
                                        type: eventType,
                                        at: nil,
                                        sessionId: nil,
                                        data: raw
                                    )
                                )
                            }
                            continue
                        }
                        if line.hasPrefix(":") { continue }
                        if line.hasPrefix("event:") {
                            eventType = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                            continue
                        }
                        if line.hasPrefix("data:") {
                            dataLines.append(
                                String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                            )
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
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
        return try await perform(request, acceptedStatuses: [expectedStatus])
    }

    private func put<T: Decodable, B: Encodable>(
        path: String,
        body: B,
        acceptedStatuses: Set<Int>,
        authorize: Bool = true,
        timeoutInterval: TimeInterval = 0
    ) async throws -> T {
        let data = try encoder.encode(body)
        let request = try makeRequest(
            path: path,
            method: "PUT",
            authorize: authorize,
            bodyData: data,
            timeoutInterval: timeoutInterval
        )
        return try await perform(request, acceptedStatuses: acceptedStatuses)
    }

    private struct OkResponse: Decodable {
        let ok: Bool?
    }

    private func postEmpty<T: Decodable>(path: String, expectedStatus: Int) async throws -> T {
        try await perform(
            try makeRequest(path: path, method: "POST", authorize: true),
            acceptedStatuses: [expectedStatus]
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
        // Mutating calls (POST/PUT) may wait on harness install; others stay snappy.
        request.timeoutInterval = timeoutInterval > 0
            ? timeoutInterval
            : (method == "POST" || method == "PUT" ? 60 : 15)

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
        acceptedStatuses: Set<Int>? = nil
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

        if let acceptedStatuses {
            if !acceptedStatuses.contains(http.statusCode) {
                throw HelmNetworkError.http(
                    http.statusCode,
                    errorMessage(from: data, fallback: HTTPURLResponse.localizedString(forStatusCode: http.statusCode))
                )
            }
        } else if !(200...299).contains(http.statusCode) {
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
