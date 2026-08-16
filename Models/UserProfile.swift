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

    // Per-sound enables — mirrors the demo's "Sounds" panel.
    var doorbellAlertsEnabled: Bool = true
    var carHornAlertsEnabled: Bool = true
    var dogBarkingAlertsEnabled: Bool = true
    var smokeAlarmAlertsEnabled: Bool = true
    var babyCryingAlertsEnabled: Bool = true

    // Transcription
    var transcriptionEnabled: Bool = true
    var keywordHighlightingEnabled: Bool = true
    var speakerDirectionEnabled: Bool = true

    // Adaptive
    var adaptiveLearningEnabled: Bool = true
    var suppressRepetitiveEnabled: Bool = true

    // Appearance
    var useDarkMode: Bool = false

    // MARK: - Codable (backward-compatible)
    // Decode new fields with defaults so older saved profiles still load.

    enum CodingKeys: String, CodingKey {
        case firstName, nicknames
        case nameDetectionEnabled, directionalArrowsEnabled, dangerSensitivity, hapticIntensity
        case doorbellAlertsEnabled, carHornAlertsEnabled, dogBarkingAlertsEnabled
        case smokeAlarmAlertsEnabled, babyCryingAlertsEnabled
        case transcriptionEnabled, keywordHighlightingEnabled, speakerDirectionEnabled
        case adaptiveLearningEnabled, suppressRepetitiveEnabled
        case useDarkMode
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        firstName                  = (try? c.decode(String.self,  forKey: .firstName)) ?? ""
        nicknames                  = (try? c.decode([String].self, forKey: .nicknames)) ?? []
        nameDetectionEnabled       = (try? c.decode(Bool.self,   forKey: .nameDetectionEnabled)) ?? true
        directionalArrowsEnabled   = (try? c.decode(Bool.self,   forKey: .directionalArrowsEnabled)) ?? true
        dangerSensitivity          = (try? c.decode(Float.self,  forKey: .dangerSensitivity)) ?? 0.66
        hapticIntensity            = (try? c.decode(Float.self,  forKey: .hapticIntensity)) ?? 0.66
        doorbellAlertsEnabled      = (try? c.decode(Bool.self,   forKey: .doorbellAlertsEnabled)) ?? true
        carHornAlertsEnabled       = (try? c.decode(Bool.self,   forKey: .carHornAlertsEnabled)) ?? true
        dogBarkingAlertsEnabled    = (try? c.decode(Bool.self,   forKey: .dogBarkingAlertsEnabled)) ?? true
        smokeAlarmAlertsEnabled    = (try? c.decode(Bool.self,   forKey: .smokeAlarmAlertsEnabled)) ?? true
        babyCryingAlertsEnabled    = (try? c.decode(Bool.self,   forKey: .babyCryingAlertsEnabled)) ?? true
        transcriptionEnabled       = (try? c.decode(Bool.self,   forKey: .transcriptionEnabled)) ?? true
        keywordHighlightingEnabled = (try? c.decode(Bool.self,   forKey: .keywordHighlightingEnabled)) ?? true
        speakerDirectionEnabled    = (try? c.decode(Bool.self,   forKey: .speakerDirectionEnabled)) ?? true
        adaptiveLearningEnabled    = (try? c.decode(Bool.self,   forKey: .adaptiveLearningEnabled)) ?? true
        suppressRepetitiveEnabled  = (try? c.decode(Bool.self,   forKey: .suppressRepetitiveEnabled)) ?? true
        useDarkMode                = (try? c.decode(Bool.self,   forKey: .useDarkMode)) ?? false
    }

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
