// ReaderSettings.swift
// Settings sheet for reader typography and layout customization.

import SwiftUI

struct ReaderSettings: View {
    @Binding var fontSize: Double
    @Binding var lineHeight: Double
    @Binding var fontFamily: String
    @Binding var horizontalPadding: Double
    @Binding var verticalPadding: Double
    @Binding var backgroundColorHex: String
    @Binding var textColorHex: String
    @Binding var bionicReading: Bool
    @Binding var lineFocusEnabled: Bool
    @Binding var lineFocusLines: Int
    @Binding var lineFocusDulling: String
    @Binding var characterSpacing: Double
    @Binding var wordSpacing: Double
    @Binding var grainIntensity: Double
    let isEmbedded: Bool

    @State private var localFontSize: Double
    @State private var localLineHeight: Double
    @State private var localHorizontalPadding: Double
    @State private var localVerticalPadding: Double
    @State private var localCharacterSpacing: Double
    @State private var localWordSpacing: Double
    @State private var localMargins: Double
    @State private var localFontFamily: String
    @State private var localBackgroundColorHex: String
    @State private var localTextColorHex: String
    @State private var localBionicReading: Bool
    @State private var localLineFocusEnabled: Bool
    @State private var localLineFocusLines: Int
    @State private var localLineFocusDulling: String
    @State private var localGrainIntensity: Double
    @State private var localFocusOverride: String
    
    @AppStorage("reader.isCustomizing") private var isCustomizing: Bool = false
    @AppStorage("reader.justifyText") private var justifyText = true
    @AppStorage("reader.keepScreenOn") private var keepScreenOn = true
    @ObservedObject private var focusManager = FocusModeManager.shared

    init(
        fontSize: Binding<Double>,
        lineHeight: Binding<Double>,
        fontFamily: Binding<String>,
        horizontalPadding: Binding<Double>,
        verticalPadding: Binding<Double>,
        backgroundColorHex: Binding<String>,
        textColorHex: Binding<String>,
        bionicReading: Binding<Bool>,
        lineFocusEnabled: Binding<Bool>,
        lineFocusLines: Binding<Int>,
        lineFocusDulling: Binding<String>,
        characterSpacing: Binding<Double>,
        wordSpacing: Binding<Double>,
        grainIntensity: Binding<Double>,
        isEmbedded: Bool = false
    ) {
        self._fontSize = fontSize
        self._lineHeight = lineHeight
        self._fontFamily = fontFamily
        self._horizontalPadding = horizontalPadding
        self._verticalPadding = verticalPadding
        self._backgroundColorHex = backgroundColorHex
        self._textColorHex = textColorHex
        self._bionicReading = bionicReading
        self._lineFocusEnabled = lineFocusEnabled
        self._lineFocusLines = lineFocusLines
        self._lineFocusDulling = lineFocusDulling
        self._characterSpacing = characterSpacing
        self._wordSpacing = wordSpacing
        self._grainIntensity = grainIntensity
        self.isEmbedded = isEmbedded

        self._localFontSize = State(initialValue: fontSize.wrappedValue)
        self._localLineHeight = State(initialValue: lineHeight.wrappedValue)
        self._localHorizontalPadding = State(initialValue: horizontalPadding.wrappedValue)
        self._localVerticalPadding = State(initialValue: verticalPadding.wrappedValue)
        self._localCharacterSpacing = State(initialValue: characterSpacing.wrappedValue)
        self._localWordSpacing = State(initialValue: wordSpacing.wrappedValue)
        self._localFontFamily = State(initialValue: fontFamily.wrappedValue)
        self._localBackgroundColorHex = State(initialValue: backgroundColorHex.wrappedValue)
        self._localTextColorHex = State(initialValue: textColorHex.wrappedValue)
        self._localBionicReading = State(initialValue: bionicReading.wrappedValue)
        self._localLineFocusEnabled = State(initialValue: lineFocusEnabled.wrappedValue)
        self._localLineFocusLines = State(initialValue: lineFocusLines.wrappedValue)
        self._localLineFocusDulling = State(initialValue: lineFocusDulling.wrappedValue)
        self._localGrainIntensity = State(initialValue: grainIntensity.wrappedValue)
        self._localFocusOverride = State(initialValue: FocusModeManager.shared.overrideType)
        
        let paddingVal = horizontalPadding.wrappedValue
        self._localMargins = State(initialValue: (paddingVal / 48.0) * 100.0)
    }

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
        let isBold: Bool
        let isSerif: Bool
        let isPremium: Bool
    }

    private let presets: [PresetTheme] = [
        PresetTheme(name: "Original", bg: "", text: "", isBold: false, isSerif: false, isPremium: false),
        PresetTheme(name: "Quiet", bg: "#0A0A0C", text: "#BDBBC5", isBold: false, isSerif: false, isPremium: false),
        PresetTheme(name: "Paper", bg: "#1C1C1E", text: "#E5E5EA", isBold: false, isSerif: false, isPremium: false),
        PresetTheme(name: "Bold", bg: "#000000", text: "#FFFFFF", isBold: true, isSerif: false, isPremium: false),
        PresetTheme(name: "Calm", bg: "#362E26", text: "#EADBCC", isBold: false, isSerif: true, isPremium: false),
        PresetTheme(name: "Focus", bg: "#1C1B16", text: "#E6DEC9", isBold: false, isSerif: false, isPremium: false),
        PresetTheme(name: "Daylight", bg: "#FFFFFF", text: "#24282E", isBold: false, isSerif: false, isPremium: false),
        PresetTheme(name: "Ivory", bg: "#F8F3E8", text: "#39352E", isBold: false, isSerif: true, isPremium: false),
        PresetTheme(name: "Sepia", bg: "#F5E6CE", text: "#514030", isBold: false, isSerif: true, isPremium: false),
        PresetTheme(name: "Sage", bg: "#E6EDE5", text: "#293C32", isBold: false, isSerif: true, isPremium: false),
        PresetTheme(name: "Dusk", bg: "#242135", text: "#E0DAEA", isBold: false, isSerif: false, isPremium: false),
        PresetTheme(name: "Midnight", bg: "#101827", text: "#D6E0EE", isBold: false, isSerif: false, isPremium: false),
        PresetTheme(name: "Forest", bg: "#15241F", text: "#D6E6DD", isBold: false, isSerif: true, isPremium: false)
    ]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("reader.highlightColor") private var highlightColorHex = ""
    @AppStorage("reader.highlightOpacity") private var highlightOpacity = 0.26
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if isEmbedded {
            content
                .onDisappear {
                    commitChanges()
                }
        } else {
            NavigationStack {
                content
                    .navigationTitle("Reader Settings")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done", role: .confirm) {
                                commitChanges()
                                dismiss()
                            }
                        }
                    }
            }
            .onDisappear { commitChanges() }
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            // Pinned Preview at the top
            pinnedPreview
            
            Form {
                themeSection

                if isCustomizing {
                    spacingSection
                    typographySection
                    moreLayoutSection
                }
                
                lineFocusSection
                focusSection
            }
            .animation(AppMotion.gentle(reduceMotion: reduceMotion), value: isCustomizing)
            .animation(AppMotion.gentle(reduceMotion: reduceMotion), value: localLineFocusEnabled)
        }
        .onChange(of: localFontSize) { _, _ in commitIfEmbedded() }
        .onChange(of: localLineHeight) { _, _ in commitIfEmbedded() }
        .onChange(of: localFontFamily) { _, _ in commitIfEmbedded() }
        .onChange(of: localHorizontalPadding) { _, _ in commitIfEmbedded() }
        .onChange(of: localVerticalPadding) { _, _ in commitIfEmbedded() }
        .onChange(of: localBackgroundColorHex) { _, _ in commitIfEmbedded() }
        .onChange(of: localTextColorHex) { _, _ in commitIfEmbedded() }
        .onChange(of: localBionicReading) { _, _ in commitIfEmbedded() }
        .onChange(of: localLineFocusEnabled) { _, _ in commitIfEmbedded() }
        .onChange(of: localLineFocusLines) { _, _ in commitIfEmbedded() }
        .onChange(of: localLineFocusDulling) { _, _ in commitIfEmbedded() }
        .onChange(of: localCharacterSpacing) { _, _ in commitIfEmbedded() }
        .onChange(of: localWordSpacing) { _, _ in commitIfEmbedded() }
        .onChange(of: localGrainIntensity) { _, _ in commitIfEmbedded() }
    }

    private var themesGrid: some View {
        ScrollView(.horizontal) {
          HStack(spacing: 12) {
            ForEach(presets) { preset in
                ThemePickerCard(
                    preset: preset,
                    isSelected: isSelected(preset)
                ) {
                    localBackgroundColorHex = preset.bg
                    localTextColorHex = preset.text
                    commitIfEmbedded()
                }
                .frame(width: 108)
                .accessibilityAddTraits(isSelected(preset) ? .isSelected : [])
            }
          }
          .padding(.vertical, 4)
          .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
        .padding(.vertical, 4)
    }

    private var themeSection: some View {
        Section("Theme & Colors") {
            themesGrid

            Toggle("Paper texture", isOn: Binding(get: { localGrainIntensity > 0 }, set: { localGrainIntensity = $0 ? 10 : 0 }))
            if localGrainIntensity > 0 {
                sliderRow("Grain intensity", symbol: "circle.dotted", value: $localGrainIntensity, range: 0...100, step: 5, valueText: "\(Int(localGrainIntensity))%")
            }

            ColorPicker("Word highlight", selection: Binding(
                get: { Color(hex: ReaderAppearance.highlightHex(background: localBackgroundColorHex, custom: highlightColorHex)) ?? .green },
                set: { if let hex = $0.toHex() { highlightColorHex = hex } }
            ), supportsOpacity: false)
            if !highlightColorHex.isEmpty {
                Button("Use theme highlight") { highlightColorHex = "" }
            }
            sliderRow("Highlight strength", symbol: "highlighter", value: $highlightOpacity, range: 0.1...0.65, step: 0.05, valueText: "\(Int(highlightOpacity * 100))%")

            Toggle("Customize", isOn: $isCustomizing.animation(AppMotion.gentle(reduceMotion: reduceMotion)))
        }
    }

    /// A labelled slider as one Form row: title and value on top, slider below.
    private func sliderRow(
        _ title: LocalizedStringKey, symbol: String, value: Binding<Double>,
        range: ClosedRange<Double>, step: Double, valueText: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent {
                Text(valueText).monospacedDigit()
            } label: {
                Label(title, systemImage: symbol)
            }
            Slider(value: value, in: range, step: step)
                .accessibilityLabel(title)
                .accessibilityValue(valueText)
        }
    }

    private var spacingSection: some View {
        Section("Spacing") {
            sliderRow("Line spacing", symbol: "arrow.up.and.down.text.horizontal", value: $localLineHeight, range: 1.0...2.5, step: 0.05, valueText: String(format: "%.2f", localLineHeight))
            sliderRow("Character spacing", symbol: "arrow.left.and.right", value: $localCharacterSpacing, range: -5...30, step: 1, valueText: "\(Int(localCharacterSpacing))%")
            sliderRow("Word spacing", symbol: "text.alignleft", value: $localWordSpacing, range: 0...50, step: 2, valueText: "\(Int(localWordSpacing))%")
            sliderRow("Margins", symbol: "square", value: $localMargins, range: 0...100, step: 5, valueText: "\(Int(localMargins))%")
                .onChange(of: localMargins) { _, newValue in
                    localHorizontalPadding = (newValue / 100.0) * 48.0
                }
        }
    }

    private var typographySection: some View {
        Section("Typography") {
            Picker("Font", selection: $localFontFamily) {
                ForEach(fontFamilies, id: \.self) { font in
                    Text(font)
                        .font(.custom(font, size: 15, relativeTo: .subheadline))
                        .tag(font)
                }
            }

            Stepper(value: $localFontSize, in: 12...32, step: 1) {
                LabeledContent("Font size", value: "\(Int(localFontSize))px")
            }
        }
    }

    private var moreLayoutSection: some View {
        Section("Custom Layout & Colors") {
            Stepper(value: $localVerticalPadding, in: 0...80, step: 4) {
                LabeledContent("Vertical padding", value: "\(Int(localVerticalPadding))px")
            }
            
            Toggle("Bionic Reading", isOn: $localBionicReading)
            Toggle("Justify Text", isOn: $justifyText)
            Toggle("Keep Screen On", isOn: $keepScreenOn)
            
            ColorPicker("Custom Background", selection: customBgColorBinding)
            ColorPicker("Custom Text Color", selection: customTextColorBinding)
        }
    }

    private var focusSection: some View {
        Section {
            Picker("Active Focus display", selection: $localFocusOverride) {
                Text("Off").tag("none")
                Text("System auto").tag("auto")
                Text("Do Not Disturb").tag("dnd")
                Text("Work Focus").tag("work")
                Text("Sleep Focus").tag("sleep")
            }
            .pickerStyle(.menu)

            if localFocusOverride == "auto" {
                focusAuthorizationRow
            }
        } header: {
            Text("Focus Integration")
        } footer: {
            Text("Show the active Focus mode (moon, work, sleep) near the top of the reader area.")
        }
    }

    @ViewBuilder
    private var focusAuthorizationRow: some View {
        let authStatus = focusManager.authorizationStatus
        if authStatus == 0 { // notDetermined
            Button("Allow Access to Focus Status") {
                focusManager.requestAuthorization()
            }
        } else if authStatus == 1 { // denied
            Label("Access to Focus status has been denied. You can enable it in iOS Settings > Privacy & Security > Focus.", systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(AppTheme.warning)
        } else if authStatus == 2 { // authorized
            LabeledContent("Active Focus", value: focusManager.isFocused ? focusManager.currentFocusType.displayName : "None")
        }
    }

    private var lineFocusSection: some View {
        Section("Line Focus") {
            Toggle("Line Focus Mode", isOn: $localLineFocusEnabled.animation(AppMotion.gentle(reduceMotion: reduceMotion)))

            if localLineFocusEnabled {
                Picker("Focused lines", selection: $localLineFocusLines) {
                    Text("1 Line").tag(1)
                    Text("2 Lines").tag(2)
                    Text("3 Lines").tag(3)
                }
                Picker("Background dulling", selection: $localLineFocusDulling) {
                    Text("Low").tag("low")
                    Text("Medium").tag("mid")
                    Text("High").tag("high")
                }
            }
        }
    }

    private func resolvedLineFocusOpacity(dulling: String) -> Double {
        switch dulling {
        case "low": return 0.3
        case "high": return 0.75
        default: return 0.5
        }
    }

    private var pinnedPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Preview").font(Typography.caption).foregroundStyle(.secondary)
                Spacer()
                Text("Spoken word").font(.caption).foregroundStyle(resolvedLocalTextColor)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background((Color(hex: ReaderAppearance.highlightHex(background: localBackgroundColorHex, custom: highlightColorHex)) ?? .green).opacity(highlightOpacity), in: .rect(cornerRadius: 5))
            }
            .padding(.horizontal, 16).padding(.top, 12)
            
            Group {
                if localBionicReading {
                    ("The quick brown fox jumps over the lazy dog. "
                    + "This preview shows how text appears with your current settings.")
                    .bionicFormatted()
                } else {
                    Text(
                        "The quick brown fox jumps over the lazy dog. "
                        + "This preview shows how text appears with your current settings."
                    )
                }
            }
            .font(localFontFamily == "System" ? .system(size: localFontSize) : .custom(localFontFamily, size: localFontSize))
            .lineSpacing((localLineHeight - 1.0) * localFontSize)
            .tracking(localCharacterSpacing * 0.1)
            .padding(.horizontal, localHorizontalPadding)
            .padding(.vertical, localVerticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(resolvedLocalTextColor)
            .background(
                resolvedLocalBackgroundColor
                    .overlay {
                        if localGrainIntensity > 0 {
                            NoiseView(intensity: localGrainIntensity)
                                .allowsHitTesting(false)
                        }
                    }
            )
            .overlay {
                if localLineFocusEnabled {
                    let focusHeight = (Double(localLineFocusLines) + 0.2) * localLineHeight * localFontSize
                    let opacity = resolvedLineFocusOpacity(dulling: localLineFocusDulling)
                    
                    VStack(spacing: 0) {
                        Color.black.opacity(opacity)
                        
                        Color.clear
                            .frame(height: focusHeight)
                            .overlay(
                                VStack {
                                    Divider()
                                    Spacer()
                                    Divider()
                                }
                            )
                        
                        Color.black.opacity(opacity)
                    }
                    .allowsHitTesting(false)
                }
            }
            .frame(height: 165, alignment: .topLeading)
            .clipped()
            .clipShape(.rect(cornerRadius: 12))
            .transaction { $0.animation = nil }
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

    // MARK: - Helpers

    private func isSelected(_ preset: PresetTheme) -> Bool {
        return localBackgroundColorHex == preset.bg && localTextColorHex == preset.text
    }

    private var resolvedLocalBackgroundColor: Color {
        if localBackgroundColorHex.isEmpty {
            return Color(light: Color(hue: 0.10, saturation: 0.08, brightness: 0.98),
                         dark: Color(hue: 0.10, saturation: 0.05, brightness: 0.12))
        }
        return Color(hex: localBackgroundColorHex) ?? .white
    }

    private var resolvedLocalTextColor: Color {
        if localTextColorHex.isEmpty {
            return Color(light: Color(hue: 0.0, saturation: 0.0, brightness: 0.12),
                         dark: Color(hue: 0.0, saturation: 0.0, brightness: 0.90))
        }
        return Color(hex: localTextColorHex) ?? .black
    }

    private var customBgColorBinding: Binding<Color> {
        Binding(
            get: {
                if let color = Color(hex: localBackgroundColorHex) {
                    return color
                }
                return .white
            },
            set: { newColor in
                if let hex = newColor.toHex() {
                    localBackgroundColorHex = hex
                    commitIfEmbedded()
                }
            }
        )
    }

    private var customTextColorBinding: Binding<Color> {
        Binding(
            get: {
                if let color = Color(hex: localTextColorHex) {
                    return color
                }
                return .black
            },
            set: { newColor in
                if let hex = newColor.toHex() {
                    localTextColorHex = hex
                    commitIfEmbedded()
                }
            }
        )
    }

    private func commitChanges() {
        fontSize = localFontSize
        lineHeight = localLineHeight
        fontFamily = localFontFamily
        horizontalPadding = localHorizontalPadding
        verticalPadding = localVerticalPadding
        backgroundColorHex = localBackgroundColorHex
        textColorHex = localTextColorHex
        bionicReading = localBionicReading
        lineFocusEnabled = localLineFocusEnabled
        lineFocusLines = localLineFocusLines
        lineFocusDulling = localLineFocusDulling
        characterSpacing = localCharacterSpacing
        wordSpacing = localWordSpacing
        grainIntensity = localGrainIntensity
        FocusModeManager.shared.overrideType = localFocusOverride
        FocusModeManager.shared.updateFocusStatus()
    }

    private func commitIfEmbedded() {
        if isEmbedded {
            commitChanges()
        }
    }
}

// MARK: - ThemePickerCard Component

struct ThemePickerCard: View {
    let preset: ReaderSettings.PresetTheme
    let isSelected: Bool
    let action: () -> Void
    
    private var cardFill: Color {
        preset.bg.isEmpty ? Color(.secondarySystemBackground) : (Color(hex: preset.bg) ?? Color(.secondarySystemBackground))
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text("Aa")
                    .font(.system(.title, design: preset.isSerif ? .serif : .default, weight: preset.isBold ? .bold : .regular))
                    .foregroundStyle(preset.text.isEmpty ? .primary : (Color(hex: preset.text) ?? .primary))
                
                Text(preset.name)
                    .font(Typography.caption)
                    .foregroundStyle(preset.text.isEmpty ? .secondary : (Color(hex: preset.text) ?? .secondary))
                    .opacity(preset.text.isEmpty ? 1.0 : 0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 80)
            .background(cardFill, in: .rect(cornerRadius: 16))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color(hex: ReaderAppearance.highlightHex(background: preset.bg)) ?? .primary, lineWidth: 3)
                }
            }
            .contentShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - NoiseView for Preview Paper Texture

struct NoiseView: View {
    let intensity: Double

    var body: some View {
        if let tile = ReaderAppearance.paperTile {
            Image(decorative: tile, scale: 1)
                .resizable(resizingMode: .tile)
                .blendMode(.softLight)
                .opacity(min(1, max(0, intensity / 100)))
                .accessibilityHidden(true)
        }
    }
}
