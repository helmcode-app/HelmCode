//
//  VFSGitModels.swift
//  HelmCode
//
//  Wire types for runner-core git RPCs:
//  vfs/gitStatus · vfs/gitRefs · vfs/gitDiff · vfs/gitShow · vfs/gitCheckout
//

import Foundation

// MARK: - Status

enum VFSGitChangeStatus: String, Codable, Sendable {
    case added
    case modified
    case deleted
    case untracked
    case renamed
}

struct VFSGitChangeEntry: Codable, Sendable, Equatable {
    let path: String
    let status: VFSGitChangeStatus
    let staged: Bool
    let fromPath: String?

    enum CodingKeys: String, CodingKey {
        case path, status, staged, fromPath
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        path = try c.decode(String.self, forKey: .path)
        status = try c.decode(VFSGitChangeStatus.self, forKey: .status)
        staged = try c.decodeIfPresent(Bool.self, forKey: .staged) ?? false
        fromPath = try c.decodeIfPresent(String.self, forKey: .fromPath)
    }
}

struct VFSGitStatusResult: Codable, Sendable, Equatable {
    let isRepo: Bool
    let branch: String?
    let upstream: String?
    let ahead: Int?
    let behind: Int?
    let changes: [VFSGitChangeEntry]

    enum CodingKeys: String, CodingKey {
        case isRepo, branch, upstream, ahead, behind, changes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isRepo = try c.decodeIfPresent(Bool.self, forKey: .isRepo) ?? false
        branch = try c.decodeIfPresent(String.self, forKey: .branch)
        upstream = try c.decodeIfPresent(String.self, forKey: .upstream)
        ahead = try c.decodeIfPresent(Int.self, forKey: .ahead)
        behind = try c.decodeIfPresent(Int.self, forKey: .behind)
        changes = try c.decodeIfPresent([VFSGitChangeEntry].self, forKey: .changes) ?? []
    }
}

// MARK: - Refs

struct VFSGitRefEntry: Codable, Sendable, Equatable {
    let name: String
    let tip: String?
    let isCurrent: Bool

    enum CodingKeys: String, CodingKey {
        case name, tip, isCurrent
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        tip = try c.decodeIfPresent(String.self, forKey: .tip)
        isCurrent = try c.decodeIfPresent(Bool.self, forKey: .isCurrent) ?? false
    }
}

struct VFSGitRefsResult: Codable, Sendable, Equatable {
    let isRepo: Bool
    let localBranches: [VFSGitRefEntry]
    let remoteBranches: [VFSGitRefEntry]
    let tags: [VFSGitRefEntry]

    enum CodingKeys: String, CodingKey {
        case isRepo, localBranches, remoteBranches, tags
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isRepo = try c.decodeIfPresent(Bool.self, forKey: .isRepo) ?? false
        localBranches = try c.decodeIfPresent([VFSGitRefEntry].self, forKey: .localBranches) ?? []
        remoteBranches = try c.decodeIfPresent([VFSGitRefEntry].self, forKey: .remoteBranches) ?? []
        tags = try c.decodeIfPresent([VFSGitRefEntry].self, forKey: .tags) ?? []
    }
}

// MARK: - Diff / show / checkout

struct VFSGitDiffParams: Encodable, Sendable {
    let path: String
    let staged: Bool
}

struct VFSGitDiffResult: Codable, Sendable, Equatable {
    let path: String
    let staged: Bool
    let diff: String
    let truncated: Bool

    enum CodingKeys: String, CodingKey {
        case path, staged, diff, truncated
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        path = try c.decode(String.self, forKey: .path)
        staged = try c.decodeIfPresent(Bool.self, forKey: .staged) ?? false
        diff = try c.decodeIfPresent(String.self, forKey: .diff) ?? ""
        truncated = try c.decodeIfPresent(Bool.self, forKey: .truncated) ?? false
    }
}

struct VFSGitShowParams: Encodable, Sendable {
    let path: String
    let revision: String
}

struct VFSGitShowResult: Codable, Sendable, Equatable {
    let path: String
    let revision: String
    let exists: Bool
    let content: String
    let truncated: Bool
    let binary: Bool

    enum CodingKeys: String, CodingKey {
        case path, revision, exists, content, truncated, binary
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        path = try c.decode(String.self, forKey: .path)
        revision = try c.decodeIfPresent(String.self, forKey: .revision) ?? "HEAD"
        exists = try c.decodeIfPresent(Bool.self, forKey: .exists) ?? false
        content = try c.decodeIfPresent(String.self, forKey: .content) ?? ""
        truncated = try c.decodeIfPresent(Bool.self, forKey: .truncated) ?? false
        binary = try c.decodeIfPresent(Bool.self, forKey: .binary) ?? false
    }
}

enum VFSGitRefKind: String, Codable, Sendable {
    case localBranch
    case remoteBranch
    case tag
}

struct VFSGitCheckoutParams: Encodable, Sendable {
    let ref: String
    let kind: VFSGitRefKind
}

struct VFSGitCheckoutResult: Codable, Sendable, Equatable {
    let ref: String
    let kind: VFSGitRefKind
    let branch: String?
    let detached: Bool

    enum CodingKeys: String, CodingKey {
        case ref, kind, branch, detached
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ref = try c.decode(String.self, forKey: .ref)
        kind = try c.decode(VFSGitRefKind.self, forKey: .kind)
        branch = try c.decodeIfPresent(String.self, forKey: .branch)
        detached = try c.decodeIfPresent(Bool.self, forKey: .detached) ?? false
    }
}
