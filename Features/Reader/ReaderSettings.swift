// ReaderSettings.swift
// Settings sheet for reader typography and layout customization.

import SwiftUI

struct ReaderSettings: View {
    @Binding var fontSize: Double
    @Binding var lineHeight: Double
    @Binding var fontFamily: String
    @Binding var horizontalPadding: Double

    private let fontFamilies = [
        "Georgia", "Palatino", "Times New Roman",
        "System", "Helvetica Neue", "Avenir",
        "Charter", "Iowan Old Style",
    ]

    var body: some View {
        NavigationStack {
            Form {
                typographySection
                layoutSection
                previewSection
            }
            .navigationTitle("Reader Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Sections

    private var typographySection: some View {
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
    }

    private var layoutSection: some View {
        Section("Layout") {
            VStack(alignment: .leading) {
                Text("Horizontal Padding: \(Int(horizontalPadding))px")
                    .font(Typography.caption)
                Slider(value: $horizontalPadding, in: 0...48, step: 4)
                    .tint(AppTheme.accent)
            }
        }
    }

    private var previewSection: some View {
        Section("Preview") {
            Text(
                "The quick brown fox jumps over the lazy dog. "
                + "This preview shows how text appears with your current settings."
            )
            .font(.custom(fontFamily, size: fontSize))
            .lineSpacing((lineHeight - 1.0) * fontSize)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 8)
        }
    }
}
