//
//  SidebarNavigator.swift
//  HelmCode
//
//  Xcode-style navigator tabs for the project sidebar.
//

import SwiftUI

enum SidebarNavigator: String, CaseIterable, Identifiable, Sendable {
    case files
    case search
    case bookmarks
    case sourceControl

    var id: String { rawValue }

    var title: String {
        switch self {
        case .files: return "Files"
        case .search: return "Search"
        case .bookmarks: return "Bookmarks"
        case .sourceControl: return "Source Control"
        }
    }

    var systemImage: String {
        switch self {
        case .files: return "folder"
        case .search: return "magnifyingglass"
        case .bookmarks: return "bookmark"
        case .sourceControl: return "arrow.triangle.branch"
        }
    }
}
