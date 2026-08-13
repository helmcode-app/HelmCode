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
    /// Read-only CodeMirror merge diff from Source Control (`vfs/gitShow` + worktree).
    case viewingDiff(project: WorkspaceProject, diff: SourceControlDiffRequest)
}
