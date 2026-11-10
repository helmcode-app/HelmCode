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

    var percentLabel: String {
        if used <= 0 { return "0%" }
        let pct = (fraction * 100).rounded()
        if pct < 1 { return "<1%" }
        return "\(Int(pct))%"
    }

    var contextLabel: String {
        "\(percentLabel) / \(Self.compactTokens(size))"
    }

    /// Used / size, rounded to the nearest whole percent.
    var percentUsed: Int {
        if used > 0 && fraction < 0.01 { return 1 }
        return Int((fraction * 100).rounded())
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
        // Lenient: OpenCode / experimental agents may omit size or send stringy numbers.
        used = (try? Self.decodeToken(container, forKey: .used)) ?? 0
        let decodedSize = (try? Self.decodeToken(container, forKey: .size)) ?? 0
        size = decodedSize > 0 ? decodedSize : 200_000
        cost = try? container.decodeIfPresent(SessionUsageCost.self, forKey: .cost)
    }

    static func parse(from meta: [String: JSONValue]?, fallbackSize: Int? = nil) -> SessionUsage? {
        guard let meta else { return nil }
        if let nested = meta["usage"]?.objectValue {
            return parse(object: nested, fallbackSize: fallbackSize)
        }
        return parse(object: meta, fallbackSize: fallbackSize)
    }

    static func parse(object: [String: JSONValue], fallbackSize: Int? = nil) -> SessionUsage? {
        guard let used = extractUsedTokens(from: object) else { return nil }
        let size = object["size"]?.intValue
            ?? object["context_size"]?.intValue
            ?? object["contextSize"]?.intValue
            ?? object["context_window"]?.intValue
            ?? object["max_tokens"]?.intValue
            ?? fallbackSize
            ?? 200_000
        guard size > 0 else { return nil }

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

    private static func extractUsedTokens(from object: [String: JSONValue]) -> Int? {
        if let u = object["used"]?.intValue { return u }
        if let t = object["totalTokens"]?.intValue ?? object["total_tokens"]?.intValue ?? object["tokens"]?.intValue {
            return t
        }
        let inp = object["inputTokens"]?.intValue
            ?? object["input_tokens"]?.intValue
            ?? object["prompt_tokens"]?.intValue
            ?? 0
        let out = object["outputTokens"]?.intValue
            ?? object["output_tokens"]?.intValue
            ?? object["completion_tokens"]?.intValue
            ?? 0
        let cached = object["cachedReadTokens"]?.intValue
            ?? object["cache_read_input_tokens"]?.intValue
            ?? 0
        let sum = inp + out + cached
        if sum > 0 { return sum }
        return nil
    }

    /// Parse harness labels (`200k`, `1m`, `272k`) into token counts.
    static func tokens(fromContextLabel raw: String) -> Int? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }
        var number = trimmed
        var multiplier = 1.0
        if trimmed.hasSuffix("k") {
            multiplier = 1_000
            number = String(trimmed.dropLast())
        } else if trimmed.hasSuffix("m") {
            multiplier = 1_000_000
            number = String(trimmed.dropLast())
        } else if trimmed.hasSuffix("b") {
            multiplier = 1_000_000_000
            number = String(trimmed.dropLast())
        }
        guard let amount = Double(number.trimmingCharacters(in: .whitespaces)),
              amount > 0 else { return nil }
        return Int((amount * multiplier).rounded())
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
        if let value = try? container.decode(String.self, forKey: key),
           let parsed = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return Int(parsed)
        }
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
