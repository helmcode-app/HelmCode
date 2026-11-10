//
//  AppBundleInfo.swift
//  HelmCode
//
//  Read-only Bundle.main metadata for Settings / About.
//

import Foundation

enum AppBundleInfo {
    static let displayName = "HelmCode"

    /// Official site (landing page, Terms, Privacy).
    static let websiteURL = URL(string: "https://www.helmcode.app")!
    static let termsOfServiceURL = URL(string: "https://www.helmcode.app/terms/")!
    static let privacyPolicyURL = URL(string: "https://www.helmcode.app/privacy/")!

    static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "—"
    }

    static var shortVersion: String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    /// `1.0 (42)` when build is present; otherwise short version only.
    static var versionLabel: String? {
        guard let short = shortVersion else { return nil }
        if let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String,
           !build.isEmpty,
           build != short {
            return "\(short) (\(build))"
        }
        return short
    }
}
