// ReaderSettings.swift
// Settings sheet for reader typography and layout customization.

import SwiftUI

struct ReaderSettings: View {
    @Binding var fontSize: Double
    @Binding var lineHeight: Double
    @Binding var fontFamily: String
    @Binding var horizontalPadding: Double
    @Binding var backgroundColorHex: String
    @Binding var textColorHex: String

    private let fontFamilies = [
        "Georgia", "Palatino", "Times New Roman",
        "System", "Helvetica Neue", "Avenir",
        "Charter", "Iowan Old Style", "Open-Dyslexic",
    ]

    struct PresetTheme: Identifiable {
        var id: String { name }
        let name: String
        let bg: String
        let text: String
    }

    private let presets: [PresetTheme] = [
        PresetTheme(name: "System", bg: "", text: ""),
        PresetTheme(name: "Light", bg: "#F5F5FA", text: "#111111"),
        PresetTheme(name: "Sepia", bg: "#F7DFC6", text: "#593100"),
        PresetTheme(name: "Green", bg: "#DCE5E2", text: "#000000"),
        PresetTheme(name: "Dark", bg: "#292832", text: "#CCCCCC"),
        PresetTheme(name: "Black", bg: "#000000", text: "#FFFFFFB3")
    ]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Pinned Preview at the top
                pinnedPreview
                
                // Form with configuration sections
                Form {
                    typographySection
                    colorsSection
                    layoutSection
                }
            }
            .navigationTitle("Reader Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private var pinnedPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preview")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 16)
                .padding(.top, 12)
            
            Text(
                "The quick brown fox jumps over the lazy dog. "
                + "This preview shows how text appears with your current settings."
            )
            .font(.custom(fontFamily, size: fontSize))
            .lineSpacing((lineHeight - 1.0) * fontSize)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundColor(resolvedTextColor)
            .background(resolvedBackgroundColor)
            .cornerRadius(12)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 3)
        }
        .background(settingsBackground)
    }

    private var settingsBackground: Color {
        #if os(iOS)
        return Color(uiColor: .systemGroupedBackground)
        #else
        return Color(nsColor: .windowBackgroundColor)
        #endif
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

    private var colorsSection: some View {
        Section("Theme & Colors") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Preset Themes")
                    .font(Typography.caption)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 12) {
                    ForEach(presets) { preset in
                        VStack(spacing: 6) {
                            PresetThemeCircle(
                                preset: preset,
                                isSelected: isSelected(preset)
                            ) {
                                backgroundColorHex = preset.bg
                                textColorHex = preset.text
                            }
                            
                            Text(preset.name)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, 4)
            }
            
            ColorPicker("Custom Background", selection: customBgColorBinding)
            ColorPicker("Custom Text Color", selection: customTextColorBinding)
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



    // MARK: - Helpers

    private func isSelected(_ preset: PresetTheme) -> Bool {
        return backgroundColorHex == preset.bg && textColorHex == preset.text
    }

    private var resolvedBackgroundColor: Color {
        if backgroundColorHex.isEmpty {
            return Color(light: Color(hue: 0.10, saturation: 0.08, brightness: 0.98),
                         dark: Color(hue: 0.10, saturation: 0.05, brightness: 0.12))
        }
        return Color(hex: backgroundColorHex) ?? .white
    }

    private var resolvedTextColor: Color {
        if textColorHex.isEmpty {
            return Color(light: Color(hue: 0.0, saturation: 0.0, brightness: 0.12),
                         dark: Color(hue: 0.0, saturation: 0.0, brightness: 0.90))
        }
        return Color(hex: textColorHex) ?? .black
    }

    private var customBgColorBinding: Binding<Color> {
        Binding(
            get: {
                if let color = Color(hex: backgroundColorHex) {
                    return color
                }
                return .white
            },
            set: { newColor in
                if let hex = newColor.toHex() {
                    backgroundColorHex = hex
                }
            }
        )
    }

    private var customTextColorBinding: Binding<Color> {
        Binding(
            get: {
                if let color = Color(hex: textColorHex) {
                    return color
                }
                return .black
            },
            set: { newColor in
                if let hex = newColor.toHex() {
                    textColorHex = hex
                }
            }
        )
    }
}

// MARK: - PresetThemeCircle Component

struct PresetThemeCircle: View {
    let preset: ReaderSettings.PresetTheme
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        ZStack {
            if preset.bg.isEmpty {
                // System theme adaptive representation
                LinearGradient(
                    colors: [Color.white, Color.black],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else if let color = Color(hex: preset.bg) {
                color
            } else {
                Color.clear
            }

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(
                        preset.text.isEmpty
                            ? .primary
                            : (Color(hex: preset.text) ?? .primary)
                    )
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
        )
        .shadow(radius: 1)
        .contentShape(Circle())
        .onTapGesture {
            action()
        }
    }
}
