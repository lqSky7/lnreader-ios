// ReaderSettingsView.swift
// Reader typography, layout, and behavior settings.

import SwiftUI

struct ReaderSettingsView: View {
    @AppStorage("reader.fontSize") private var fontSize: Double = 18
    @AppStorage("reader.lineHeight") private var lineHeight: Double = 1.6
    @AppStorage("reader.fontFamily") private var fontFamily = "Georgia"
    @AppStorage("reader.padding") private var horizontalPadding: Double = 16
    @AppStorage("reader.justifyText") private var justifyText = true
    @AppStorage("reader.keepScreenOn") private var keepScreenOn = true

    private let fontFamilies = [
        "Georgia", "Palatino", "Times New Roman",
        "System", "Helvetica Neue", "Avenir",
        "Charter", "Iowan Old Style",
    ]

    var body: some View {
        Form {
            Section("Typography") {
                Picker("Font", selection: $fontFamily) {
                    ForEach(fontFamilies, id: \.self) { font in
                        Text(font)
                            .font(.custom(font, size: 15))
                            .tag(font)
                    }
                }

                VStack(alignment: .leading) {
                    Text("Font Size: \(Int(fontSize))px")
                        .font(Typography.caption)
                    Slider(value: $fontSize, in: 12...32, step: 1)
                        .tint(AppTheme.accent)
                }

                VStack(alignment: .leading) {
                    Text("Line Height: \(String(format: "%.1f", lineHeight))")
                        .font(Typography.caption)
                    Slider(value: $lineHeight, in: 1.0...2.5, step: 0.1)
                        .tint(AppTheme.accent)
                }
            }

            Section("Layout") {
                VStack(alignment: .leading) {
                    Text("Horizontal Padding: \(Int(horizontalPadding))px")
                        .font(Typography.caption)
                    Slider(value: $horizontalPadding, in: 0...48, step: 4)
                        .tint(AppTheme.accent)
                }

                Toggle("Justify text", isOn: $justifyText)
            }

            Section("Behavior") {
                Toggle("Keep screen on", isOn: $keepScreenOn)
            }

            Section("Preview") {
                Text(
                    "The quick brown fox jumps over the lazy dog. "
                    + "This preview shows how text appears with your current settings."
                )
                .font(.custom(fontFamily, size: fontSize))
                .lineSpacing((lineHeight - 1.0) * fontSize)
                .multilineTextAlignment(justifyText ? .leading : .leading)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, 8)
            }
        }
        .navigationTitle("Reader")
        .navigationBarTitleDisplayMode(.inline)
    }
}
