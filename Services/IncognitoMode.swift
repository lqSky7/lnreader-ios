// IncognitoMode.swift
// A global switch that stops the app recording what you read.

import Foundation
import Observation

/// While on, the session leaves no trace: no `History` row is written, no
/// `Entry.lastReadAt` is touched, no chapter flips to read, and no tracker is
/// told anything.
///
/// Reading position is still saved. Losing your place is destructive, and the
/// position lives on the chapter you opened rather than in a record of what you
/// read — so it is the one thing incognito keeps.
///
/// Persisted across launches on purpose: `V2_PROGRESS` R13 requires it to be
/// visible so it can never be on by accident, which is why the readers and the
/// History toolbar both show it.
@Observable
@MainActor
final class IncognitoMode {

    static let shared = IncognitoMode()

    static let defaultsKey = "history.incognito"

    private(set) var isOn: Bool

    private init() {
        isOn = UserDefaults.standard.bool(forKey: Self.defaultsKey)
    }

    func toggle() {
        set(!isOn)
    }

    func set(_ on: Bool) {
        guard on != isOn else { return }
        isOn = on
        UserDefaults.standard.set(on, forKey: Self.defaultsKey)
    }
}
