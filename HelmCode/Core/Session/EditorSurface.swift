//
//  EditorSurface.swift
//  HelmCode
//
//  Center-column surface driven by project / file selection.
//

import Foundation

enum EditorSurface: Equatable {
    case welcome
    case emptyProject(WorkspaceProject)
    case editing(project: WorkspaceProject, file: WorkspaceNode)
}
