// AboutView.swift
// App info, version, and links.

import SwiftUI

struct AboutView: View {
    var body: some View {
        Form {
            Section {
                header
            }

            Section("App") {
                LabeledContent("Version", value: versionString)
                LabeledContent("Build", value: buildString)
                LabeledContent("Bundle ID", value: bundleID)
            }

            Section("Links") {
                Link("LNReader on GitHub", destination: URL(string: "https://github.com/LNReader/lnreader")!)
                Link(
                    "Plugin Registry",
                    destination: URL(string: "https://github.com/LNReader/lnreader-plugins")!
                )
            }
        }
        .settingsScreen("About")
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "book.fill")
                .font(.largeTitle)
                .foregroundStyle(.primary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(appName)
                    .font(Typography.title)

                Text("Liquid Glass port of LNReader")
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "LNReader"
    }

    private var versionString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "1.0"
    }

    private var buildString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            ?? "1"
    }

    private var bundleID: String {
        Bundle.main.bundleIdentifier ?? "unknown"
    }
}
