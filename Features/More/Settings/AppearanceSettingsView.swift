// AppearanceSettingsView.swift
// Theme, glass effects, and cover styling.

import SwiftUI

struct AppearanceSettingsView: View {
    @AppStorage("appearance.colorScheme") private var colorSchemeRaw = AppearanceScheme.system.rawValue
    @AppStorage("appearance.useLargeTitles") private var useLargeTitles = true
    @AppStorage("appearance.showCoverShadows") private var showCoverShadows = true

    var body: some View {
        Form {
            Section("Theme") {
                Picker("Color Scheme", selection: colorScheme) {
                    ForEach(AppearanceScheme.allCases) { scheme in
                        Text(scheme.label).tag(scheme)
                    }
                }

                Toggle("Use large titles", isOn: $useLargeTitles)
            }

            Section("Covers") {
                Toggle("Show cover shadows", isOn: $showCoverShadows)
            }
        }
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var colorScheme: Binding<AppearanceScheme> {
        Binding(
            get: { AppearanceScheme(rawValue: colorSchemeRaw) ?? .system },
            set: { colorSchemeRaw = $0.rawValue }
        )
    }
}

private enum AppearanceScheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}
