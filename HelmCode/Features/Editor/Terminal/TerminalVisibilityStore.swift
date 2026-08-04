//
//  TerminalVisibilityStore.swift
//  HelmCode
//
//  Project Terminal panel visibility (⌘J).
//
//  Why not only @AppStorage?
//  After shell `exit`, WK bridge callbacks update the flag; the next key-command
//  action can still see a *stale* @AppStorage snapshot in the same run loop.
//  Always pair property-wrapper writes with an explicit UserDefaults write, and
//  read the persisted flag when handling ⌘J.
//

import Foundation

enum TerminalVisibilityStore {
    private static var defaults: UserDefaults { .standard }

    static var isShown: Bool {
        defaults.bool(forKey: AppStorageKey.showTerminal)
    }

    /// Persist + return the value to assign into `@AppStorage` / `@State` bindings.
    @discardableResult
    static func setShown(_ shown: Bool) -> Bool {
        defaults.set(shown, forKey: AppStorageKey.showTerminal)
        return shown
    }

    static func hide() {
        setShown(false)
    }

    static func show() {
        setShown(true)
    }
}
