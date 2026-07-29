//
//  WorkspaceCatalog.swift
//  HelmCode
//
//  Seed projects for the sidebar until live git browsing is wired.
//

import Foundation

enum WorkspaceCatalog {
    static let projects: [WorkspaceProject] = [
        WorkspaceProject(
            id: "helmcode-app",
            name: "helmcode",
            remote: "github.com/helmcode-app/helmcode",
            defaultBranch: "main",
            root: WorkspaceNode(
                id: "root-helmcode",
                name: "helmcode",
                path: "",
                isDirectory: true,
                children: [
                    file("Package.swift", "swift"),
                    dir("Sources", [
                        dir("HelmCodeCore", [
                            file("AgentClient.swift", "swift"),
                            file("TaskModels.swift", "swift"),
                        ]),
                        dir("HelmCodeUI", [
                            file("CommanderView.swift", "swift"),
                            file("EditorHost.swift", "swift"),
                        ]),
                    ]),
                    dir("Tests", [
                        file("AgentClientTests.swift", "swift"),
                    ]),
                    file("README.md", "md"),
                ],
                languageHint: nil
            )
        ),
        WorkspaceProject(
            id: "runner-core",
            name: "runner-core",
            remote: "github.com/helmcode-app/runner-core",
            defaultBranch: "main",
            root: WorkspaceNode(
                id: "root-runner",
                name: "runner-core",
                path: "",
                isDirectory: true,
                children: [
                    file("package.json", "json"),
                    dir("src", [
                        file("entrypoint.ts", "ts"),
                        file("types.ts", "ts"),
                        dir("modes", [
                            file("open-core.ts", "ts"),
                            file("commercial-saas.ts", "ts"),
                        ]),
                        dir("core", [
                            file("agent.ts", "ts"),
                            file("git.ts", "ts"),
                            file("llm.ts", "ts"),
                        ]),
                    ]),
                    dir("docs", [
                        dir("api", [
                            file("open-core.md", "md"),
                            file("shared-types.md", "md"),
                        ]),
                    ]),
                    file("Dockerfile", nil),
                ],
                languageHint: nil
            )
        ),
    ]

    private static func file(_ name: String, _ lang: String?) -> WorkspaceNode {
        WorkspaceNode(
            id: "f-\(name)-\(lang ?? "bin")",
            name: name,
            path: name,
            isDirectory: false,
            children: [],
            languageHint: lang
        )
    }

    private static func dir(_ name: String, _ children: [WorkspaceNode]) -> WorkspaceNode {
        WorkspaceNode(
            id: "d-\(name)",
            name: name,
            path: name,
            isDirectory: true,
            children: children.map { child in
                WorkspaceNode(
                    id: "\(name)/\(child.id)",
                    name: child.name,
                    path: "\(name)/\(child.path)",
                    isDirectory: child.isDirectory,
                    children: child.children,
                    languageHint: child.languageHint
                )
            },
            languageHint: nil
        )
    }
}
