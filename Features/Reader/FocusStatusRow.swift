// FocusStatusRow.swift
// One shared row for the Focus permission state, used by both reader settings
// screens. It used to be copy-pasted with the authorization statuses read as
// bare integers, which mapped `denied` onto "allowed" and `authorized` onto
// nothing at all, so the row vanished exactly when it should have shown the
// active Focus.

import SwiftUI

struct FocusStatusRow: View {
    @ObservedObject var focusManager: FocusModeManager = .shared

    var body: some View {
        switch focusManager.authorization {
        case .unavailable:
            Label(
                "Focus status is not available in this build. The reader keeps its manual Focus selector.",
                systemImage: "info.circle"
            )
            .font(.footnote)
            .foregroundStyle(.secondary)

        case .notDetermined:
            Button("Allow Access to Focus Status") {
                focusManager.requestAuthorization()
            }

        case .denied, .restricted:
            Label(
                "Access to Focus status has been denied. You can enable it in iOS Settings > Privacy & Security > Focus.",
                systemImage: "exclamationmark.triangle"
            )
            .font(.footnote)
            .foregroundStyle(AppTheme.warning)

        case .authorized:
            LabeledContent(
                "Active Focus",
                value: focusManager.isFocused ? focusManager.currentFocusType.displayName : "None"
            )
        }
    }
}
