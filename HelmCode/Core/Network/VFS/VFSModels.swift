//
//  VFSModels.swift
//  HelmCode
//
//  Codable models for runner-core `helm-vfs` core methods and notifications.
//  Git wire types live in VFSGitModels.swift. Protocol: runner-core/docs/api/vfs.md
//

import Foundation

// MARK: - Flat tree entries (`vfs/initialize`)

/// Flat entry from Go `TreeEntry` (`path`, `size`, `type`).
struct RawFileNode: Codable, Hashable, Sendable, Identifiable {
    var id: String { path }

    /// Slash-separated path relative to workspace root.
    let path: String
    let size: Int64
    /// `"file"` | `"dir"`
    let type: String

    var isDirectory: Bool {
        type == "dir"
    }

    enum CodingKeys: String, CodingKey {
        case path, size, type
    }

    init(path: String, size: Int64, type: String) {
        self.path = path
        self.size = size
        self.type = type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(String.self, forKey: .path)
        type = try container.decode(String.self, forKey: .type)
        if let int64 = try? container.decode(Int64.self, forKey: .size) {
            size = int64
        } else if let int = try? container.decode(Int.self, forKey: .size) {
            size = Int64(int)
        } else {
            size = 0
        }
    }
}

struct VFSInitializeParams: Encodable, Sendable {
    var root: String?
}

struct VFSInitializeResult: Codable, Sendable, Equatable {
    let root: String
    /// Human-facing project name from runner (git remote / env); optional for older servers.
    let name: String?
    /// Git origin display string (e.g. `github.com/org/repo`); optional for older servers.
    let remote: String?
    /// Current HEAD branch from runner; optional for older servers (do not invent `main`).
    let branch: String?
    let entries: [RawFileNode]

    enum CodingKeys: String, CodingKey {
        case root, name, remote, branch, entries
    }

    init(
        root: String,
        name: String? = nil,
        remote: String? = nil,
        branch: String? = nil,
        entries: [RawFileNode]
    ) {
        self.root = root
        self.name = name
        self.remote = remote
        self.branch = branch
        self.entries = entries
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        root = try container.decode(String.self, forKey: .root)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        remote = try container.decodeIfPresent(String.self, forKey: .remote)
        branch = try container.decodeIfPresent(String.self, forKey: .branch)
        entries = try container.decode([RawFileNode].self, forKey: .entries)
    }
}

// MARK: - Chunked read (`vfs/read_chunk`)

struct VFSReadChunkParams: Encodable, Sendable {
    let path: String
    let offset: Int64
    let limit: Int
}

struct VFSReadChunkResult: Decodable, Sendable, Equatable {
    let path: String
    let content: String
    let offset: Int64
    let bytesRead: Int
    let isEOF: Bool
    let fileSize: Int64

    enum CodingKeys: String, CodingKey {
        case path
        case content
        case offset
        case bytesRead = "bytes_read"
        case isEOF = "is_eof"
        case fileSize = "file_size"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        path = try c.decode(String.self, forKey: .path)
        content = try c.decode(String.self, forKey: .content)
        offset = Self.decodeInt64(c, key: .offset) ?? 0
        if let n = try? c.decode(Int.self, forKey: .bytesRead) {
            bytesRead = n
        } else if let n = try? c.decode(Int64.self, forKey: .bytesRead) {
            bytesRead = Int(n)
        } else {
            bytesRead = content.utf8.count
        }
        isEOF = try c.decodeIfPresent(Bool.self, forKey: .isEOF) ?? false
        fileSize = Self.decodeInt64(c, key: .fileSize) ?? 0
    }

    private static func decodeInt64(
        _ c: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) -> Int64? {
        if let v = try? c.decode(Int64.self, forKey: key) { return v }
        if let v = try? c.decode(Int.self, forKey: key) { return Int64(v) }
        return nil
    }
}

enum VFSStreamPhase: Equatable, Sendable {
    case idle
    case streaming(path: String, loaded: Int64, total: Int64)
    case complete(path: String)
    case failed(path: String, message: String)
}

struct VFSStreamProgress: Equatable, Sendable {
    var path: String
    var loadedBytes: Int64
    var totalBytes: Int64
    var isLargeFile: Bool
    var isComplete: Bool
    var isReadOnlyRecommended: Bool

    var fraction: Double {
        guard totalBytes > 0 else { return isComplete ? 1 : 0 }
        return min(1, Double(loadedBytes) / Double(totalBytes))
    }
}

/// Chunk size defaults (64 KiB matches runner-core DefaultChunkLimit).
enum VFSStreamDefaults: Sendable {
    nonisolated static let chunkLimit = 65_536
    nonisolated static let largeFileThreshold: Int64 = 2 * 1024 * 1024
}

// MARK: - Read / write

struct VFSPathParams: Encodable, Sendable {
    let path: String
}

struct VFSReadResult: Codable, Sendable, Equatable {
    let path: String
    let content: String
    let size: Int

    init(path: String, content: String, size: Int) {
        self.path = path
        self.content = content
        self.size = size
    }
}

struct VFSWriteParams: Encodable, Sendable {
    let path: String
    let content: String
}

struct VFSWriteResult: Codable, Sendable, Equatable {
    let path: String
    let size: Int
}

struct VFSEmptyParams: Encodable, Sendable {}

// Git wire types: VFSGitModels.swift

// MARK: - Notifications

enum VFSChangeType: String, Codable, Sendable {
    case write
    case create
    case remove
    case rename
}

struct VFSDidChangeParams: Codable, Sendable, Equatable {
    let path: String
    let type: VFSChangeType
}

// MARK: - Connection

enum VFSConnectionState: Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    case reconnecting(attempt: Int)
    case failed(String)

    var isReady: Bool {
        if case .connected = self { return true }
        return false
    }

    var shortTitle: String {
        switch self {
        case .disconnected: return "VFS offline"
        case .connecting: return "VFS connecting…"
        case .connected: return "VFS connected"
        case .reconnecting(let n): return "VFS reconnecting (\(n))…"
        case .failed(let msg): return "VFS error — \(msg)"
        }
    }
}
