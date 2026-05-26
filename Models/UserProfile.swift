// UserProfile.swift
// SwiftData model for user settings profile (name and avatar photo).

import Foundation
import SwiftData

@Model
final class UserProfile {
    var name: String = "Reader"
    @Attribute(.externalStorage) var avatarData: Data? = nil
    
    init(name: String = "Reader", avatarData: Data? = nil) {
        self.name = name
        self.avatarData = avatarData
    }
}
