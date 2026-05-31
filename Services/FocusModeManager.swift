// FocusModeManager.swift
// Handles Focus status and manual overrides/simulation.

import SwiftUI
#if os(iOS)
import Intents
import Combine
#endif

@MainActor
class FocusModeManager: ObservableObject {
    static let shared = FocusModeManager()
    
    @Published var isFocused: Bool = false
    @Published var authorizationStatus: Int = 0 // raw value of INFocusStatusCenter.authorizationStatus
    
    // Manual override: "auto", "none", "dnd", "work", "sleep"
    @AppStorage("focus.overrideType") var overrideType: String = "auto"
    
    private init() {
        updateFocusStatus()
        
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
        INFocusStatusCenter.default.requestAuthorization { status in
            Task { @MainActor in
                self.authorizationStatus = status.rawValue
                self.updateFocusStatus()
            }
        }
        #endif
    }
    
    func updateFocusStatus() {
        #if os(iOS)
        let status = INFocusStatusCenter.default.authorizationStatus
        self.authorizationStatus = status.rawValue
        
        if status == .authorized {
            self.isFocused = INFocusStatusCenter.default.focusStatus.isFocused ?? false
        } else {
            self.isFocused = false
        }
        #else
        self.isFocused = false
        self.authorizationStatus = 0
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
