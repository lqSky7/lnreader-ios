// ReaderSettingsView.swift
// Reader typography, layout, and behavior settings.

import SwiftUI

struct ReaderSettingsView: View {
    @AppStorage("reader.fontSize") private var fontSize: Double = 18
    @AppStorage("reader.lineHeight") private var lineHeight: Double = 1.6
    @AppStorage("reader.fontFamily") private var fontFamily = "Georgia"
    @AppStorage("reader.padding") private var horizontalPadding: Double = 16
    @AppStorage("reader.verticalPadding") private var verticalPadding: Double = 20
    @AppStorage("reader.readingMode") private var readingMode = "scroll"
    @AppStorage("reader.bionicReading") private var bionicReading = false
    @AppStorage("reader.lineFocusEnabled") private var lineFocusEnabled = false
    @AppStorage("reader.lineFocusLines") private var lineFocusLines = 1
    @AppStorage("reader.lineFocusDulling") private var lineFocusDulling = "mid"
    @AppStorage("reader.backgroundColor") private var backgroundColorHex: String = ""
    @AppStorage("reader.textColor") private var textColorHex: String = ""
    @AppStorage("reader.characterSpacing") private var characterSpacing: Double = 0.0
    @AppStorage("reader.wordSpacing") private var wordSpacing: Double = 0.0
    @AppStorage("reader.grainIntensity") private var grainIntensity: Double = 10.0

    var body: some View {
        ReaderSettings(
            fontSize: $fontSize,
            lineHeight: $lineHeight,
            fontFamily: $fontFamily,
            horizontalPadding: $horizontalPadding,
            verticalPadding: $verticalPadding,
            backgroundColorHex: $backgroundColorHex,
            textColorHex: $textColorHex,
            bionicReading: $bionicReading,
            lineFocusEnabled: $lineFocusEnabled,
            lineFocusLines: $lineFocusLines,
            lineFocusDulling: $lineFocusDulling,
            readingMode: $readingMode,
            characterSpacing: $characterSpacing,
            wordSpacing: $wordSpacing,
            grainIntensity: $grainIntensity,
            isEmbedded: true
        )
        .navigationTitle("Reader Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}
