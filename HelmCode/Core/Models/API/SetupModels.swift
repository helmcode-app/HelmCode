//
//  SetupModels.swift
//  HelmCode
//
//  First-boot pairing for runner-core (`/v1/setup/*`).
//

import Foundation

struct SetupPublicStatus: Codable, Sendable, Equatable {
    let paired: Bool
    let authRequired: Bool
}

struct SetupEnrollBody: Encodable, Sendable {
    var code: String
    var deviceName: String
}

struct SetupEnrollResponse: Codable, Sendable, Equatable {
    let status: String
    let deviceId: String?
    let token: String?
    let runnerId: String?
    let enrollmentId: String?
    let expiresAt: Double?
}

struct SetupInviteBody: Encodable, Sendable {
    var url: String
}

struct SetupDevicesResponse: Codable, Sendable, Equatable {
    let runnerId: String
    let devices: [RunnerDeviceRecord]
}

struct RunnerDeviceRecord: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let name: String
    let createdAt: String
    let lastSeenAt: String?
    let current: Bool
}

struct SetupEnrollmentsResponse: Codable, Sendable, Equatable {
    let enrollments: [SetupPendingEnrollment]
}

struct SetupPendingEnrollment: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let deviceName: String
    let createdAt: String
    let expiresAt: Double
}

struct WsTicketResponse: Codable, Sendable, Equatable {
    let ticket: String
    let expiresAt: Double
}

enum SetupEnrollError: LocalizedError {
    case denied
    case expired
    case missingToken

    var errorDescription: String? {
        switch self {
        case .denied:
            return "The other device denied this request."
        case .expired:
            return "The setup code expired. Ask for a new one, or on the runner run node dist/entrypoint.js setup:enroll."
        case .missingToken:
            return "The runner did not return a device token."
        }
    }
}

struct SetupSessionStatus: Codable, Sendable, Equatable {
    let phase: String
    let githubConfigured: Bool
    let githubLogin: String?
    let repo: SetupRepoRef?
    let hasRepo: Bool
    let paired: Bool
    /// Present after clone: which workspace was filled.
    let workspaceId: String?
    let workspaces: [SetupWorkspaceRef]?

    var canOpenProject: Bool {
        hasRepo || phase == "ready"
    }
}

struct SetupRepoRef: Codable, Sendable, Equatable {
    let owner: String
    let repo: String

    var slug: String { "\(owner)/\(repo)" }
}

struct SetupWorkspaceRef: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let path: String
    let kind: String
    let repo: SetupRepoRef?

    var displayName: String {
        if let repo { return repo.slug }
        if kind == "primary" { return "Default Repository" }
        return id
    }
}

struct GithubDeviceStart: Codable, Sendable, Equatable {
    let userCode: String
    let verificationUri: String
    let expiresAt: Double
    let intervalMs: Double
}

struct GithubPollResponse: Codable, Sendable, Equatable {
    let status: String
    let login: String?
    let intervalMs: Double?
    let error: String?
}

struct GithubReposResponse: Codable, Sendable, Equatable {
    let repos: [GithubRepoRecord]
}

struct GithubRepoRecord: Codable, Sendable, Equatable, Identifiable {
    var id: String { "\(owner)/\(repo)" }
    let owner: String
    let repo: String
    let `private`: Bool
    let defaultBranch: String

    var slug: String { "\(owner)/\(repo)" }
}

struct GithubCloneBody: Encodable, Sendable {
    var owner: String
    var repo: String
}

/// Paired runner on this iPad. Not a project — the repo is chosen later.
struct EnrolledRunner: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var url: String
    var label: String

    var displayLabel: String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return Self.hostLabel(for: url)
    }

    static func hostLabel(for raw: String) -> String {
        guard let url = URL(string: raw), let host = url.host, !host.isEmpty else { return raw }
        if let port = url.port { return "\(host):\(port)" }
        return host
    }
}

struct SetupPairTicket: Codable, Sendable, Equatable {
    let code: String
    let expiresAt: Double?
    let qrPayload: String?
    let qrDataUrl: String?
}

extension Notification.Name {
    static let helmPairingLink = Notification.Name("helmPairingLink")
}

enum RunnerPairingInbox {
    static var pending: URL?
}

enum RunnerPairingLink {
    static func parse(_ url: URL) -> (runnerURL: String, code: String)? {
        guard url.scheme == "helmcode", url.host == "pair" else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        let runner = items?.first(where: { $0.name == "url" })?.value?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let code = items?.first(where: { $0.name == "c" })?.value?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !runner.isEmpty, !code.isEmpty else { return nil }
        return (runner, code.uppercased())
    }
}
