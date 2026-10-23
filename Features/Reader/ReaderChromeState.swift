// ReaderChromeState.swift - The reader's two states.
//
// Focus: just the content. Control: every number and every action, floating on
// Liquid Glass. One tap moves between them; there is no third state.

import Foundation

enum ReaderChromeState: String, CaseIterable {
    /// Content only — nothing overlays the page.
    case focus
    /// All metadata and actions.
    case control

    var isControl: Bool { self == .control }

    var toggled: ReaderChromeState {
        self == .control ? .focus : .control
    }
}
