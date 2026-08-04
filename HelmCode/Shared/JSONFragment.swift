//
//  JSONFragment.swift
//  HelmCode
//
//  Encode Swift values as JSON *literals* for injection into evaluateJavaScript.
//

import Foundation

enum JSONFragment {
    /// JSON-encoded string literal suitable for JS source, e.g. `"hello"`.
    static func string(_ value: String) -> String {
        let data = try? JSONSerialization.data(
            withJSONObject: value,
            options: [.fragmentsAllowed]
        )
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
    }
}
