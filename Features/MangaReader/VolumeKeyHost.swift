// VolumeKeyHost.swift - Turns the hardware volume buttons into page turns.
//
// iOS exposes a button press only as a change in `AVAudioSession.outputVolume`.
// So while this is on screen it parks the system volume at the midpoint, reads
// each change as up or down (`VolumeKeyDetector`), sets the volume back to the
// midpoint, and restores the user's volume when it goes away. A hidden
// `MPVolumeView` is what keeps the system volume HUD from appearing and gives
// us the one supported way to set the volume.
//
// The catch is inherent to the technique: while the reader is open with volume
// keys enabled, the media volume is not where the user left it. It is restored
// on leaving, and whenever the app resigns active.

import AVFoundation
import MediaPlayer
import SwiftUI
import UIKit

struct VolumeKeyHost: UIViewRepresentable {
    /// Called on the main actor for each press.
    let onPress: (VolumeKey) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MPVolumeView {
        // Offscreen and near-invisible, but in the hierarchy: a detached
        // `MPVolumeView` does not suppress the HUD.
        let view = MPVolumeView(frame: CGRect(x: -2000, y: -2000, width: 1, height: 1))
        view.alpha = 0.01
        view.isUserInteractionEnabled = false
        context.coordinator.volumeView = view
        context.coordinator.start()
        return view
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {
        context.coordinator.onPress = onPress
    }

    static func dismantleUIView(_ uiView: MPVolumeView, coordinator: Coordinator) {
        coordinator.stop()
    }

    @MainActor
    final class Coordinator {
        var onPress: ((VolumeKey) -> Void)?
        weak var volumeView: MPVolumeView?

        private let target: Float = 0.5
        private var detector = VolumeKeyDetector(target: 0.5)
        private var observation: NSKeyValueObservation?
        private var observers: [NSObjectProtocol] = []
        private var savedVolume: Float?
        private var isRunning = false

        func start() {
            guard !isRunning else { return }
            isRunning = true
            let session = AVAudioSession.sharedInstance()
            // Ambient + mix: take no audio focus and interrupt nothing.
            try? session.setCategory(.ambient, options: [.mixWithOthers])
            try? session.setActive(true)

            savedVolume = session.outputVolume
            observation = session.observe(\.outputVolume, options: [.new]) { [weak self] _, change in
                guard let volume = change.newValue else { return }
                Task { @MainActor in self?.handle(volume) }
            }

            let center = NotificationCenter.default
            observers = [
                center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.suspend() }
                },
                center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.resume() }
                },
            ]
            // The slider is created lazily by `MPVolumeView`; give it a turn.
            DispatchQueue.main.async { [weak self] in self?.park() }
        }

        func stop() {
            guard isRunning else { return }
            isRunning = false
            observation?.invalidate()
            observation = nil
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            restore()
        }

        /// Set the system volume back to what the user had.
        private func restore() {
            guard let saved = savedVolume else { return }
            setSystemVolume(saved)
            savedVolume = nil
        }

        private func suspend() {
            guard isRunning else { return }
            observation?.invalidate()
            observation = nil
            restore()
        }

        private func resume() {
            guard isRunning, observation == nil else { return }
            let session = AVAudioSession.sharedInstance()
            savedVolume = session.outputVolume
            observation = session.observe(\.outputVolume, options: [.new]) { [weak self] _, change in
                guard let volume = change.newValue else { return }
                Task { @MainActor in self?.handle(volume) }
            }
            park()
        }

        private func park() {
            detector = VolumeKeyDetector(target: target)
            setSystemVolume(target)
        }

        private func handle(_ volume: Float) {
            guard isRunning else { return }
            if let key = detector.consume(volume) {
                onPress?(key)
                setSystemVolume(target)
            }
        }

        private func setSystemVolume(_ value: Float) {
            let slider = volumeView?.subviews.compactMap { $0 as? UISlider }.first
            slider?.value = value
        }
    }
}
