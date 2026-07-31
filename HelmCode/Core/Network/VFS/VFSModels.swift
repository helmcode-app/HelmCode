//
//  VFSModels.swift
//  HelmCode
//
//  Codable models for runner-core `helm-vfs` methods and notifications.
//  Protocol: runner-core/docs/api/vfs.md
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
    let entries: [RawFileNode]
}

// MARK: - Read / write

struct VFSPathParams: Encodable, Sendable {
    let path: String
}

struct VFSReadResult: Codable, Sendable, Equatable {
    let path: String
    let content: String
    let size: Int
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
