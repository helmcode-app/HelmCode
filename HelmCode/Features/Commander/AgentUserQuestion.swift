//
//  AgentUserQuestion.swift
//  HelmCode
//
//  Structured questions from LLM tool calling (e.g. Pi harness `ask_user_question`).
//

import Foundation

struct AgentQuestionOption: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let label: String
    let description: String?
    let preview: String?

    init(id: String = UUID().uuidString, label: String, description: String? = nil, preview: String? = nil) {
        self.id = id
        self.label = label
        self.description = description
        self.preview = preview
    }
}

struct AgentUserQuestion: Identifiable, Equatable, Sendable {
    let id: String
    let header: String?
    let question: String
    let multiSelect: Bool
    let options: [AgentQuestionOption]

    init(
        id: String = UUID().uuidString,
        header: String? = nil,
        question: String,
        multiSelect: Bool = false,
        options: [AgentQuestionOption]
    ) {
        self.id = id
        self.header = header
        self.question = question
        self.multiSelect = multiSelect
        self.options = options
    }

    /// Extract questions from raw JSON string or tool action content.
    static func parse(from raw: String?) -> [AgentUserQuestion] {
        guard let raw, !raw.isEmpty,
              let data = raw.data(using: .utf8)
        else { return [] }

        guard let json = try? JSONSerialization.jsonObject(with: data) else { return [] }
        return parse(from: json)
    }

    static func parse(from json: Any) -> [AgentUserQuestion] {
        if let dict = json as? [String: Any] {
            // Envelope format: { "questions": [ ... ] }
            if let array = dict["questions"] as? [[String: Any]] {
                return array.enumerated().compactMap { idx, item in
                    parseSingle(dict: item, defaultId: "q-\(idx)")
                }
            }
            // Direct single question format: { "question": "...", "options": [ ... ] }
            if let single = parseSingle(dict: dict, defaultId: "q-0") {
                return [single]
            }
        } else if let array = json as? [[String: Any]] {
            return array.enumerated().compactMap { idx, item in
                parseSingle(dict: item, defaultId: "q-\(idx)")
            }
        }
        return []
    }

    private static func parseSingle(dict: [String: Any], defaultId: String) -> AgentUserQuestion? {
        guard let question = dict["question"] as? String, !question.isEmpty else { return nil }
        let header = dict["header"] as? String
        let multiSelect = (dict["multiSelect"] as? Bool) ?? false

        var options: [AgentQuestionOption] = []
        if let rawOptions = dict["options"] as? [[String: Any]] {
            for (optIdx, opt) in rawOptions.enumerated() {
                guard let label = opt["label"] as? String, !label.isEmpty else { continue }
                let desc = opt["description"] as? String
                let prev = opt["preview"] as? String
                options.append(
                    AgentQuestionOption(
                        id: "\(defaultId)-opt-\(optIdx)",
                        label: label,
                        description: desc,
                        preview: prev
                    )
                )
            }
        }

        return AgentUserQuestion(
            id: defaultId,
            header: header,
            question: question,
            multiSelect: multiSelect,
            options: options
        )
    }
}
