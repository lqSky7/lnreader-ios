// AdvancedSettingsView.swift
// Diagnostics, experimental flags, and maintenance actions.

import SwiftUI

struct AdvancedSettingsView: View {
    @Environment(PluginManager.self) private var pluginManager

    @State private var showClearPluginsDialog = false
    @State private var showResetReaderDialog = false

    var body: some View {
        Form {
            Section("Maintenance") {
                Button("Clear plugin cache", role: .destructive) {
                    showClearPluginsDialog = true
                }

                Button("Reset reader settings", role: .destructive) {
                    showResetReaderDialog = true
                }
            }
        }
        .navigationTitle("Advanced")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Clear plugin cache?",
            isPresented: $showClearPluginsDialog,
            titleVisibility: .visible
        ) {
            Button("Clear Plugin Cache", role: .destructive) {
                clearPluginCache()
            }
        } message: {
            Text("This removes downloaded plugin files. You can reinstall them later.")
        }
        .confirmationDialog(
            "Reset reader settings?",
            isPresented: $showResetReaderDialog,
            titleVisibility: .visible
        ) {
            Button("Reset Reader Settings", role: .destructive) {
                resetReaderSettings()
            }
        } message: {
            Text("Font, line height, and padding will return to defaults.")
        }
    }

    private func clearPluginCache() {
        pluginManager.clearAllPlugins()
    }

    private func resetReaderSettings() {
        let defaults = UserDefaults.standard
        let keys = [
            "reader.fontSize",
            "reader.lineHeight",
            "reader.fontFamily",
            "reader.padding",
            "reader.justifyText",
            "reader.keepScreenOn",
            "reader.backgroundColor",
            "reader.textColor",
        ]
        for key in keys {
            defaults.removeObject(forKey: key)
        }
    }
}
