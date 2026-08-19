//
//  EnabledModelsPrefs.swift
//  HelmCode
//
//  Per-runner model enablement for the Commander picker (Cursor-style curation).
//  Storage key: helm.agent.enabledModelIDs.<normalizedRunnerURL>
//

import Foundation

enum EnabledModelsPrefs {
    static func storageKey(forRunnerURL raw: String) -> String {
        AppStorageKey.enabledModelIDsPrefix + RunnerURL.normalizeHTTP(raw)
    }

    /// `nil` when the user has not curated yet (chat shows every catalog model).
    static func load(runnerURL: String, defaults: UserDefaults = .standard) -> Set<String>? {
        let key = storageKey(forRunnerURL: runnerURL)
        guard let data = defaults.data(forKey: key),
              let ids = try? JSONDecoder().decode([String].self, from: data)
        else {
            return nil
        }
        return Set(ids)
    }

    static func save(_ ids: Set<String>, runnerURL: String, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(ids.sorted()) else { return }
        defaults.set(data, forKey: storageKey(forRunnerURL: runnerURL))
    }

    /// Remove curation for this runner — chat picker shows the full catalog again.
    static func clear(runnerURL: String, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: storageKey(forRunnerURL: runnerURL))
    }

    static func isConfigured(runnerURL: String, defaults: UserDefaults = .standard) -> Bool {
        defaults.data(forKey: storageKey(forRunnerURL: runnerURL)) != nil
    }

    /// Models for the chat picker: curated set when configured, else full catalog.
    /// Always keeps `selectedID` reachable; falls back to full catalog on empty/stale prefs.
    static func pickerModels(
        from catalog: [AgentModelOption],
        selectedID: String,
        runnerURL: String,
        defaults: UserDefaults = .standard
    ) -> [AgentModelOption] {
        let source = catalog.isEmpty ? AgentModelOption.fallbackCatalog : catalog
        guard let enabled = load(runnerURL: runnerURL, defaults: defaults), !enabled.isEmpty else {
            return source
        }

        var out = source.filter { enabled.contains($0.id) }
        if !selectedID.isEmpty, !out.contains(where: { $0.id == selectedID }) {
            if let selected = source.first(where: { $0.id == selectedID }) {
                out.insert(selected, at: 0)
            } else {
                out.insert(
                    AgentModelOption(id: selectedID, title: selectedID, subtitle: "Selected"),
                    at: 0
                )
            }
        }
        return out.isEmpty ? source : out
    }

    /// `4/27` (enabled / catalog size). `nil` when the catalog is empty.
    static func enabledOverAvailableLabel(
        catalog: [AgentModelOption],
        runnerURL: String,
        defaults: UserDefaults = .standard
    ) -> String? {
        guard !catalog.isEmpty else { return nil }
        let available = catalog.count
        let enabled: Int
        if let saved = load(runnerURL: runnerURL, defaults: defaults) {
            enabled = catalog.filter { saved.contains($0.id) }.count
        } else {
            enabled = available
        }
        return "\(enabled)/\(available)"
    }
}
