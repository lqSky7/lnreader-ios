// MangaReaderSettingsSheet.swift - Reader settings: this series, and how input behaves.

import SwiftUI

struct MangaReaderSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// Per-series layout and tap zones.
    let series: MangaSeriesSettings
    /// Volume keys, auto scroll, hold to scroll: these follow the user.
    @Binding var controls: MangaControlSettings

    var body: some View {
        NavigationStack {
            Form {
                layoutSection
                tapSection
                volumeSection
                autoScrollSection
                holdSection
            }
            // The app's accent is white in dark mode, which turned every switch
            // solid white; the rest of the app tints controls with this instead.
            .tint(AppTheme.controlFill)
            .navigationTitle("Reader settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
        // A partial-height sheet keeps the page in view above it and takes the
        // system glass material. Medium is the only detent so scrolling the
        // list can't pull the sheet up to full height.
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    // MARK: - This series

    private var layoutSection: some View {
        Section {
            Picker("Layout", selection: Binding(
                get: { series.resolved.readingMode },
                set: { series.setReadingMode($0) }
            )) {
                ForEach(MangaReadingMode.allCases) { Text($0.displayName).tag($0) }
            }
            Picker("Direction", selection: Binding(
                get: { series.resolved.direction },
                set: { series.setDirection($0) }
            )) {
                ForEach(MangaPagingDirection.allCases) { Text($0.displayName).tag($0) }
            }
            Button("Use these for all series") { series.makeDefault() }
            if series.hasOverrides {
                Button("Reset this series to the default", role: .destructive) { series.reset() }
            }
        } header: {
            Text("This series")
        } footer: {
            Text("Series you have not changed follow the default.")
        }
    }

    private var tapSection: some View {
        Section {
            Picker("Tap zones", selection: Binding(
                get: { series.resolved.tapZones },
                set: { series.setTapZones($0) }
            )) {
                ForEach(MangaTapZoneLayout.allCases) { Text($0.displayName).tag($0) }
            }
            Toggle("Invert tap zones", isOn: Binding(
                get: { series.resolved.invertTapZones },
                set: { series.setInvertTapZones($0) }
            ))
        } header: {
            Text("Tap zones")
        } footer: {
            Text(series.resolved.tapZones.summary
                + ". Paged mode turns the page, webtoon scrolls a screen. "
                + "Right-to-left reading swaps the sides automatically.")
        }
    }

    // MARK: - Input

    private var volumeSection: some View {
        Section {
            Toggle("Volume keys turn pages", isOn: $controls.volumeKeys)
            if controls.volumeKeys {
                Toggle("Invert volume keys", isOn: $controls.volumeKeysInverted)
            }
        } header: {
            Text("Volume keys")
        } footer: {
            Text(controls.volumeKeys
                ? "Volume up goes back and volume down goes forward"
                    + (controls.volumeKeysInverted ? ", inverted" : "")
                    + ". While the reader is open the media volume is held at half and restored when you leave."
                : "Use the volume buttons to turn pages or scroll.")
        }
    }

    private var autoScrollSection: some View {
        Section {
            speedSlider(
                "Speed",
                value: $controls.autoScrollSpeed,
                range: MangaControlSettings.autoSpeedRange
            )
        } header: {
            Text("Auto scroll")
        } footer: {
            Text("Webtoon mode. Start it from the reader's options menu; touching the screen pauses it.")
        }
    }

    private var holdSection: some View {
        Section {
            Toggle("Hold to scroll", isOn: $controls.holdScrollEnabled)
            if controls.holdScrollEnabled {
                speedSlider("Speed", value: $controls.hold.baseSpeed, range: HoldScrollConfig.baseRange)
                speedSlider("Slowest", value: $controls.hold.minSpeed, range: 10...600)
                speedSlider("Fastest", value: $controls.hold.maxSpeed, range: 100...3000)
                VStack(alignment: .leading) {
                    HStack {
                        Text("Change per swipe")
                        Spacer()
                        Text(String(format: "%.1f pt/s per pt", controls.hold.speedPerPoint))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $controls.hold.speedPerPoint, in: HoldScrollConfig.stepRange)
                }
                Picker("Faster when you swipe", selection: $controls.hold.upIncreases) {
                    Text("Up").tag(true)
                    Text("Down").tag(false)
                }
            }
        } header: {
            Text("Hold to scroll")
        } footer: {
            Text("Webtoon mode. Press and hold to scroll; keep holding and swipe "
                + (controls.hold.upIncreases ? "up to speed up and down to slow down" : "down to speed up and up to slow down")
                + ".")
        }
    }

    private func speedSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value.wrappedValue)) pt/s")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: value, in: range)
        }
    }
}
