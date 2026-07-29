//
//  EditorSampleLibrary.swift
//  HelmCode
//
//  Demo file buffers until the editor opens real workspace contents.
//

import Foundation

enum EditorSampleLibrary {
    static func content(for path: String, project: String) -> String {
        if path.hasSuffix(".swift") {
            return """
            // \(path)
            // \(project) — HelmCode · CodeMirror 6

            import Foundation

            public struct AgentClient: Sendable {
                public let baseURL: URL
                public var apiToken: String?

                public init(baseURL: URL, apiToken: String? = nil) {
                    self.baseURL = baseURL
                    self.apiToken = apiToken
                }

                public func submit(prompt: String) async throws -> String {
                    // Pipeline: POST /v1/tasks → 202 → poll GET /v1/tasks/:id
                    return prompt
                }
            }
            """
        }
        if path.hasSuffix(".ts") {
            return """
            // \(path)
            // runner-core open-core route surface

            export type HelmMode = "open-core" | "commercial-saas";

            export interface HealthStatus {
              ok: true;
              mode: HelmMode;
              version: string;
              uptimeMs: number;
              activeTasks: number;
            }
            """
        }
        if path.hasSuffix(".md") {
            return """
            # \(path)

            HelmCode commander console — mobile-first iPad AI coding surface.

            Connects to **runner-core** (`HELM_MODE=open-core`) on `:8080`.
            """
        }
        if path.hasSuffix(".json") {
            return """
            {
              "name": "\(project)",
              "private": true,
              "type": "module"
            }
            """
        }
        return "// \(path)\n// Select a source file to inspect its buffer.\n"
    }
}
