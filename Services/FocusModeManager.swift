// FocusModeManager.swift
// Handles Focus status and manual overrides/simulation.

import SwiftUI
#if os(iOS)
import Intents
#endif

/// How much of the user's Focus status the app is allowed to read.
///
/// `rawValue` mirrors `INFocusStatusAuthorizationStatus` exactly, but the cases
/// are named here so call sites never compare bare integers. The ordering is
/// `.notDetermined = 0`, `.restricted = 1`, `.denied = 2`, `.authorized = 3`.
/// `.unavailable` is ours: the platform cannot be asked at all, either because
/// we are not on iOS or because the built app is missing its usage description.
enum FocusAuthorization: Int, Equatable {
    case unavailable = -1
    case notDetermined = 0
    case restricted = 1
    case denied = 2
    case authorized = 3

    var canRequestAccess: Bool { self == .notDetermined }

    var isAuthorized: Bool { self == .authorized }

    /// True when the user said no in a way they can undo in Settings.
    var isDenied: Bool { self == .denied || self == .restricted }

    var displayName: String {
        switch self {
        case .unavailable: return "Unavailable"
        case .notDetermined: return "Not requested"
        case .restricted: return "Restricted"
        case .denied: return "Denied"
        case .authorized: return "Allowed"
        }
    }
}

@MainActor
final class FocusModeManager: ObservableObject {
    static let shared = FocusModeManager()

    @Published private(set) var isFocused: Bool = false
    @Published private(set) var authorization: FocusAuthorization = .unavailable

    /// Manual override: "auto", "none", "dnd", "work", "sleep".
    ///
    /// This used to be `@AppStorage`, which reads and writes `UserDefaults` but
    /// never tells `ObservableObject` subscribers, so changing the override left
    /// every view showing the old Focus type. Persisting by hand keeps the
    /// published value and the stored value in step.
    @Published var overrideType: String = "auto" {
        didSet {
            guard overrideType != oldValue else { return }
            defaults.set(overrideType, forKey: Self.overrideKey)
        }
    }

    private static let overrideKey = "focus.overrideType"
    private let defaults = UserDefaults.standard

    /// `INFocusStatusCenter` terminates the process when the app has no
    /// `NSFocusStatusUsageDescription`, and that check is invisible to the type
    /// checker, so a plist regression would only surface as a crash on launch.
    /// Read the built bundle first and refuse to call the framework if the key
    /// is missing or blank.
    private static var hasUsageDescription: Bool {
        #if os(iOS)
        guard let value = Bundle.main.object(forInfoDictionaryKey: "NSFocusStatusUsageDescription") as? String else {
            return false
        }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        #else
        return false
        #endif
    }

    private init() {
        overrideType = defaults.string(forKey: Self.overrideKey) ?? "auto"

        // Deliberately no Intents access here. `init()` runs the first time
        // anything touches `.shared`, which can be during launch, and privacy
        // APIs are at their most fragile at that moment. The first refresh
        // happens from `didBecomeActive` or an explicit call once a view is up.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    @objc private func appDidBecomeActive() {
        updateFocusStatus()
    }

    func requestAuthorization() {
        #if os(iOS)
        guard Self.hasUsageDescription else {
            authorization = .unavailable
            return
        }
        guard !authorization.isAuthorized else { return }

        INFocusStatusCenter.default.requestAuthorization { [weak self] status in
            Task { @MainActor in
                guard let self else { return }
                self.authorization = FocusAuthorization(rawValue: status.rawValue) ?? .notDetermined
                self.updateFocusStatus()
            }
        }
        #else
        authorization = .unavailable
        #endif
    }

    func updateFocusStatus() {
        #if os(iOS)
        guard Self.hasUsageDescription else {
            authorization = .unavailable
            isFocused = false
            return
        }

        let status = INFocusStatusCenter.default.authorizationStatus
        authorization = FocusAuthorization(rawValue: status.rawValue) ?? .notDetermined

        guard status == .authorized else {
            isFocused = false
            return
        }

        isFocused = INFocusStatusCenter.default.focusStatus.isFocused ?? false
        #else
        authorization = .unavailable
        isFocused = false
        #endif
    }

    var currentFocusType: FocusType {
        if overrideType != "auto" {
            return FocusType(rawValue: overrideType) ?? .none
        }

        guard isFocused else { return .none }

        let calendar = Calendar.current
        let now = Date()
        let hour = calendar.component(.hour, from: now)
        let weekday = calendar.component(.weekday, from: now)

        if hour >= 22 || hour < 7 {
            return .sleep
        }

        if weekday >= 2 && weekday <= 6 && hour >= 9 && hour < 17 {
            return .work
        }

        return .dnd
    }
}

enum FocusType: String, CaseIterable, Identifiable {
    case none
    case dnd
    case work
    case sleep

    var id: String { self.rawValue }

    var iconName: String {
        switch self {
        case .none: return ""
        case .dnd: return "moon.fill"
        case .work: return "briefcase.fill"
        case .sleep: return "bed.double.fill"
        }
    }

    var displayName: String {
        switch self {
        case .none: return "No Focus"
        case .dnd: return "Do Not Disturb"
        case .work: return "Work Focus"
        case .sleep: return "Sleep Focus"
        }
    }
}
