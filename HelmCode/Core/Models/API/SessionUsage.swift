//
//  SessionUsage.swift
//  HelmCode
//
//  ACP `usage_update` snapshot: context window + optional cost.
//  Wire field on AgentSessionDTO / SessionHistoryEnvelope.
//

import Foundation

/// Session-level context window + optional cumulative cost.
struct SessionUsage: Codable, Sendable, Equatable {
    var used: Int
    var size: Int
    var cost: SessionUsageCost?

    enum CodingKeys: String, CodingKey {
        case used, size, cost
    }

    var fraction: Double {
        guard size > 0 else { return 0 }
        return min(1, Double(used) / Double(size))
    }

    var contextLabel: String {
        "\(Self.compactTokens(used)) / \(Self.compactTokens(size))"
    }

    var costLabel: String? {
        guard let cost else { return nil }
        return Self.formatCost(cost)
    }

    init(used: Int, size: Int, cost: SessionUsageCost? = nil) {
        self.used = used
        self.size = size
        self.cost = cost
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        used = try Self.decodeToken(container, forKey: .used)
        size = try Self.decodeToken(container, forKey: .size)
        cost = try container.decodeIfPresent(SessionUsageCost.self, forKey: .cost)
    }

    static func parse(from meta: [String: JSONValue]?) -> SessionUsage? {
        guard let meta else { return nil }
        if let nested = meta["usage"]?.objectValue {
            return parse(object: nested)
        }
        return parse(object: meta)
    }

    static func parse(object: [String: JSONValue]) -> SessionUsage? {
        guard let used = object["used"]?.intValue,
              let size = object["size"]?.intValue,
              size > 0 else { return nil }
        let cost: SessionUsageCost?
        if let raw = object["cost"]?.objectValue,
           let amount = raw["amount"]?.numberValue,
           let currency = raw["currency"]?.stringValue,
           !currency.isEmpty {
            cost = SessionUsageCost(amount: amount, currency: currency)
        } else {
            cost = nil
        }
        return SessionUsage(used: used, size: size, cost: cost)
    }

    static func compactTokens(_ count: Int) -> String {
        let value = Double(count)
        if count >= 1_000_000 {
            let scaled = value / 1_000_000
            return formatScaled(scaled, suffix: "M")
        }
        if count >= 1_000 {
            let scaled = value / 1_000
            return formatScaled(scaled, suffix: "K")
        }
        return "\(count)"
    }

    static func formatCost(_ cost: SessionUsageCost) -> String {
        let amount = cost.amount
        let code = cost.currency.uppercased()
        let formatted: String
        if amount >= 1 {
            formatted = String(format: "%.2f", amount)
        } else {
            formatted = String(format: "%.3f", amount)
        }
        if code == "USD" {
            return "$\(formatted)"
        }
        return "\(formatted) \(code)"
    }

    private static func formatScaled(_ value: Double, suffix: String) -> String {
        if abs(value.rounded() - value) < 0.05 {
            return "\(Int(value.rounded()))\(suffix)"
        }
        return String(format: "%.1f\(suffix)", value)
    }

    private static func decodeToken(
        _ container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> Int {
        if let value = try? container.decode(Int.self, forKey: key) { return value }
        if let value = try? container.decode(Double.self, forKey: key) { return Int(value) }
        throw DecodingError.keyNotFound(key, .init(
            codingPath: container.codingPath,
            debugDescription: "Missing \(key.stringValue)"
        ))
    }
}

struct SessionUsageCost: Codable, Sendable, Equatable {
    var amount: Double
    var currency: String
}
