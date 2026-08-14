//
//  HelmCodeNetworkEngine.swift
//  HelmCode
//
//  Runner HTTP probe: GET /health + GET /v1/status.
//  Agent turns live on AgentNetworkEngine → /v1/sessions.
//

import Combine
import Foundation

/// UI-facing connection probe for the open project's runner.
@MainActor
final class HelmCodeNetworkEngine: ObservableObject {

    @Published private(set) var connectionState: BackendConnectionState = .unknown
    @Published private(set) var health: HealthCheck?
    @Published private(set) var runtimeStatus: RuntimeStatus?
    @Published private(set) var helmMode: HelmMode = .openCore
    @Published private(set) var lastError: String?

    @Published var baseURLString: String {
        didSet { api.baseURLString = baseURLString }
    }

    @Published var apiToken: String {
        didSet { api.apiToken = apiToken }
    }

    private var api: RunnerCoreAPIClient

    init(
        // Docker compose maps host 18080 → container 8080 (see runner-core compose.dev.yaml).
        baseURL: String = "http://127.0.0.1:18080",
        apiToken: String = "",
        session: URLSession = .shared
    ) {
        self.baseURLString = baseURL
        self.apiToken = apiToken
        self.api = RunnerCoreAPIClient(
            baseURLString: baseURL,
            apiToken: apiToken,
            session: session
        )
    }

    func checkBackendHealth() async {
        connectionState = .checking
        lastError = nil

        do {
            let healthBody = try await api.health()
            health = healthBody
            helmMode = healthBody.mode
            connectionState = .online

            if let statusBody = try? await api.status() {
                runtimeStatus = statusBody
                helmMode = statusBody.mode
            }
        } catch {
            health = nil
            runtimeStatus = nil
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            connectionState = .offline(message)
            lastError = message
        }
    }
}
