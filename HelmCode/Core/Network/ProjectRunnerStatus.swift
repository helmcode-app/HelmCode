//
//  ProjectRunnerStatus.swift
//  HelmCode
//
//  Per-project runner-core reachability (each project may use a different API).
//  UI glyph: `ProjectRunnerStatusIcon` in Shared/UI.
//

import Combine
import Foundation

// MARK: - Reachability

/// Connectivity of a project’s runner-core HTTP API (`GET /health`).
enum ProjectRunnerReachability: Equatable, Sendable {
    /// Local/demo project with no runner URL.
    case none
    case checking
    case online
    case offline

    var accessibilityLabel: String {
        switch self {
        case .none: return "No runner configured"
        case .checking: return "Checking runner"
        case .online: return "Runner reachable"
        case .offline: return "Runner unreachable"
        }
    }
}

// MARK: - Probe

enum RunnerHealthProbe {
    /// Lightweight independent health check (does not mutate global engines).
    static func isReachable(baseURL: String, apiToken: String? = nil, timeout: TimeInterval = 4) async -> Bool {
        guard let url = RunnerURL.healthURL(fromBase: baseURL) else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let token = apiToken?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200..<300).contains(http.statusCode)
        } catch {
            return false
        }
    }
}

// MARK: - Monitor

/// Probes each project’s `runnerBaseURL` independently for list trailing icons.
@MainActor
final class ProjectRunnerStatusMonitor: ObservableObject {
    @Published private(set) var statusByProjectID: [WorkspaceProject.ID: ProjectRunnerReachability] = [:]

    private var tasks: [WorkspaceProject.ID: Task<Void, Never>] = [:]
    /// Cache by normalized URL so several projects on the same host share one probe.
    private var resultByURL: [String: ProjectRunnerReachability] = [:]

    func status(for project: WorkspaceProject) -> ProjectRunnerReachability {
        statusByProjectID[project.id] ?? (project.normalizedRunnerURL == nil ? .none : .checking)
    }

    /// Refresh connectivity for the given projects (cancels stale probes).
    func refresh(projects: [WorkspaceProject], apiToken: String?) {
        let ids = Set(projects.map(\.id))
        for key in tasks.keys where !ids.contains(key) {
            tasks[key]?.cancel()
            tasks[key] = nil
            statusByProjectID.removeValue(forKey: key)
        }

        for project in projects {
            refresh(project: project, apiToken: apiToken)
        }
    }

    func refresh(project: WorkspaceProject, apiToken: String?) {
        guard let url = project.normalizedRunnerURL else {
            tasks[project.id]?.cancel()
            tasks[project.id] = nil
            statusByProjectID[project.id] = ProjectRunnerReachability.none
            return
        }

        if let cached = resultByURL[url], cached == .online || cached == .offline {
            // Show last result immediately, then re-probe.
            statusByProjectID[project.id] = cached
        } else {
            statusByProjectID[project.id] = .checking
        }

        tasks[project.id]?.cancel()
        let projectID = project.id
        tasks[projectID] = Task { [weak self] in
            let online = await RunnerHealthProbe.isReachable(baseURL: url, apiToken: apiToken)
            guard !Task.isCancelled else { return }
            let next: ProjectRunnerReachability = online ? .online : .offline
            self?.resultByURL[url] = next
            self?.statusByProjectID[projectID] = next
            self?.tasks[projectID] = nil
        }
    }

    /// Prefer live VFS/engine state when this project is the active connection.
    func displayStatus(
        for project: WorkspaceProject,
        activeBaseURL: String?,
        vfsState: VFSConnectionState
    ) -> ProjectRunnerReachability {
        if project.normalizedRunnerURL == nil { return .none }

        if let active = activeBaseURL.flatMap({ RunnerURL.isValid($0) ? RunnerURL.normalizeHTTP($0) : nil }),
           let projectURL = project.normalizedRunnerURL,
           active == projectURL {
            switch vfsState {
            case .connected: return .online
            case .connecting, .reconnecting: return .checking
            case .failed: return .offline
            case .disconnected: return status(for: project)
            }
        }
        return status(for: project)
    }

    /// Convenience for list rows (engine + live VFS).
    func displayStatus(
        for project: WorkspaceProject,
        engine: HelmCodeNetworkEngine,
        vfs: VFSNetworkEngine
    ) -> ProjectRunnerReachability {
        displayStatus(
            for: project,
            activeBaseURL: engine.baseURLString,
            vfsState: vfs.connectionState
        )
    }

    /// Refresh using the app’s active HTTP token.
    func refresh(projects: [WorkspaceProject], engine: HelmCodeNetworkEngine) {
        refresh(projects: projects, apiToken: engine.apiToken)
    }
}
