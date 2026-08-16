// UserProfile.swift
// User identity, preferences, and adaptive settings. Persisted locally via UserDefaults.

import Foundation

struct UserProfile: Codable, Equatable {

    // Identity
    var firstName: String = ""
    var nicknames: [String] = []

    // Awareness
    var nameDetectionEnabled: Bool = true
    var directionalArrowsEnabled: Bool = true
    var dangerSensitivity: Float = 0.66
    var hapticIntensity: Float = 0.66

    // Transcription
    var transcriptionEnabled: Bool = true
    var keywordHighlightingEnabled: Bool = true
    var speakerDirectionEnabled: Bool = true

    // Adaptive
    var adaptiveLearningEnabled: Bool = true
    var suppressRepetitiveEnabled: Bool = true

    // Appearance
    var useDarkMode: Bool = false

    /// All names + nicknames that should trigger name detection.
    var allDetectionNames: [String] {
        var names: [String] = []
        let trimmedFirst = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedFirst.isEmpty {
            names.append(trimmedFirst)
        }
        for nick in nicknames {
            let trimmed = nick.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                names.append(trimmed)
            }
        }
        return names
    }

    // MARK: - Persistence

    private static let storageKey = "pulse.profile"

    static func load() -> UserProfile {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let profile = try? JSONDecoder().decode(UserProfile.self, from: data)
        else { return UserProfile() }
        return profile
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: UserProfile.storageKey)
    }
}
