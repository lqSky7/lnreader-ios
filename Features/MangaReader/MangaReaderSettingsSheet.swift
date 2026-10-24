// MangaReaderSettingsSheet.swift - Reader settings: this series, and how input behaves.

import SwiftUI

struct MangaReaderSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// Per-series layout and tap zones.
    let series: MangaSeriesSettings
    /// Volume keys, auto scroll, hold to scroll: these follow the user.
    @Binding var controls: MangaControlSettings

    /// Opens full height; half height is one drag down.
    @State private var detent: PresentationDetent = .large
    @AppStorage(Haptics.enabledKey) private var hapticsEnabled = true
    @AppStorage(Haptics.scrollEnabledKey) private var scrollHaptics = true

    var body: some View {
        NavigationStack {
            Form {
                layoutSection
                tapSection
                stripSection
                volumeSection
                autoScrollSection
                holdSection
                hapticsSection
            }
            .navigationTitle("Reader settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
        // Full height by default, so every setting is in reach; half height is
        // one drag down and keeps the page in view above the sheet.
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
    }

    private var hapticsSection: some View {
        Section {
            Toggle("Scroll haptics", isOn: $scrollHaptics)
                .disabled(!hapticsEnabled)
                .onChange(of: scrollHaptics) { _, on in
                    if on { Haptics.shared.scroll(ScrollFeel.detent(speed: 800)) }
                }
        } header: {
            Text("Haptics")
        } footer: {
            Text(hapticsEnabled
                ? "A soft swell as you scroll: rising as you read on, falling as you scroll back, "
                    + "and stronger the faster you flick. The master switch and strength live in "
                    + "Settings › General › Haptics."
                : "All vibration is off in Settings › General › Haptics.")
        }
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

    private var stripSection: some View {
        Section {
            VStack(alignment: .leading) {
                HStack {
                    Text("Width")
                    Spacer()
                    Text("\(Int((controls.stripWidth * 100).rounded()))%")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $controls.stripWidth, in: MangaControlSettings.stripWidthRange, step: 0.05)
            }
            Picker("Momentum", selection: $controls.momentum) {
                ForEach(WebtoonMomentum.allCases) { Text($0.displayName).tag($0) }
            }
        } header: {
            Text("Webtoon strip")
        } footer: {
            Text("A narrower strip leaves still margins on both sides, so less of what you see is moving. "
                + "Momentum is how far the strip glides after a flick.")
        }
    }

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
            Picker("Style", selection: $controls.autoScrollStyle) {
                ForEach(AutoScrollStyle.allCases) { Text($0.displayName).tag($0) }
            }
            speedSlider(
                controls.autoScrollStyle == .stepped ? "Pace" : "Speed",
                value: $controls.autoScrollSpeed,
                range: MangaControlSettings.autoSpeedRange
            )
        } header: {
            Text("Auto scroll")
        } footer: {
            Text("Webtoon mode. Start it from the reader's options menu; touching the screen pauses it."
                + (controls.autoScrollStyle == .stepped
                    ? " The strip stays still while you read, then moves a screen, keeping the same average pace."
                    : ""))
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
