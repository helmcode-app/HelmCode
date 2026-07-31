//
//  VFSJSONRPC.swift
//  HelmCode
//
//  JSON-RPC 2.0 wire types for runner-core VFS (`docs/api/vfs.md`).
//

import Foundation

enum VFSJSONRPC {
    static let version = "2.0"
}

// MARK: - Request / response

struct VFSJSONRPCRequest<P: Encodable>: Encodable {
    let jsonrpc: String = VFSJSONRPC.version
    let id: Int
    let method: String
    let params: P
}

struct VFSJSONRPCRequestNoParams: Encodable {
    let jsonrpc: String = VFSJSONRPC.version
    let id: Int
    let method: String
}

/// Inbound frame: response (has `id`) or notification (has `method`, no usable `id`).
struct VFSJSONRPCInbound: Decodable {
    let jsonrpc: String?
    let id: VFSJSONRPCID?
    let method: String?
    let result: JSONValue?
    let error: VFSJSONRPCErrorBody?
    let params: JSONValue?

    var isNotification: Bool {
        method != nil && id == nil
    }

    var isResponse: Bool {
        id != nil
    }
}

enum VFSJSONRPCID: Codable, Hashable, Sendable {
    case int(Int)
    case string(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            throw DecodingError.typeMismatch(
                VFSJSONRPCID.self,
                .init(codingPath: decoder.codingPath, debugDescription: "id must be int or string")
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .int(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        }
    }

    var intValue: Int? {
        switch self {
        case .int(let value): return value
        case .string(let value): return Int(value)
        }
    }
}

struct VFSJSONRPCErrorBody: Codable, Sendable, Equatable {
    let code: Int
    let message: String
    let data: JSONValue?
}

/// Wrapper for JSON-RPC success payloads: `{ "result": … }`.
struct VFSJSONRPCResultBox<T: Decodable>: Decodable {
    let result: T
}

// MARK: - Errors

enum VFSError: LocalizedError, Equatable {
    case invalidURL
    case notConnected
    case encoding(String)
    case decoding(String)
    case rpc(code: Int, message: String)
    case timeout
    case closed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid VFS WebSocket URL."
        case .notConnected: return "VFS is not connected."
        case .encoding(let message): return "VFS encode error: \(message)"
        case .decoding(let message): return "VFS decode error: \(message)"
        case .rpc(let code, let message): return "VFS RPC \(code): \(message)"
        case .timeout: return "VFS request timed out."
        case .closed(let message): return "VFS closed: \(message)"
        }
    }
}
