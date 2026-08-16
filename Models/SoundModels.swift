// SoundModels.swift
// Core data models for sound classification, direction, and detections.

import Foundation
import SwiftUI

// MARK: - SoundType

enum SoundType: String, Codable, Hashable, CaseIterable {
    case siren
    case fireAlarm
    case carHorn
    case glassBreaking
    case explosion
    case crash
    case aggressiveYelling
    case doorbell
    case knocking
    case babyCrying
    case dogBarking
    case phoneRinging
    case nearbyConversation
    case musicPlaying
    case trafficNoise
    case nameDetected

    var displayName: String {
        switch self {
        case .siren:               return "Siren"
        case .fireAlarm:           return "Fire Alarm"
        case .carHorn:             return "Car Horn"
        case .glassBreaking:       return "Glass Breaking"
        case .explosion:           return "Explosion"
        case .crash:               return "Crash"
        case .aggressiveYelling:   return "Yelling"
        case .doorbell:            return "Doorbell"
        case .knocking:            return "Knocking"
        case .babyCrying:          return "Baby Crying"
        case .dogBarking:          return "Dog Barking"
        case .phoneRinging:        return "Phone Ringing"
        case .nearbyConversation:  return "Conversation"
        case .musicPlaying:        return "Music"
        case .trafficNoise:        return "Traffic"
        case .nameDetected:        return "Name Called"
        }
    }

    var isDangerous: Bool {
        switch self {
        case .siren, .fireAlarm, .glassBreaking, .explosion, .crash, .aggressiveYelling:
            return true
        default:
            return false
        }
    }

    var isSpeech: Bool {
        switch self {
        case .nearbyConversation, .nameDetected, .aggressiveYelling:
            return true
        default:
            return false
        }
    }

    var isAlert: Bool {
        switch self {
        case .doorbell, .knocking, .phoneRinging, .carHorn:
            return true
        default:
            return false
        }
    }

    var systemImageName: String {
        switch self {
        case .siren:               return "light.beacon.max.fill"
        case .fireAlarm:           return "flame.fill"
        case .carHorn:             return "car.fill"
        case .glassBreaking:       return "exclamationmark.triangle.fill"
        case .explosion:           return "burst.fill"
        case .crash:               return "exclamationmark.octagon.fill"
        case .aggressiveYelling:   return "person.wave.2.fill"
        case .doorbell:            return "bell.fill"
        case .knocking:            return "hand.tap.fill"
        case .babyCrying:          return "figure.and.child.holdinghands"
        case .dogBarking:          return "pawprint.fill"
        case .phoneRinging:        return "phone.fill"
        case .nearbyConversation:  return "bubble.left.and.bubble.right.fill"
        case .musicPlaying:        return "music.note"
        case .trafficNoise:        return "car.2.fill"
        case .nameDetected:        return "person.fill.questionmark"
        }
    }

    var categoryColor: Color {
        if isDangerous {
            return Color(red: 0.91, green: 0.23, blue: 0.10)  // #e83b1a
        } else if isSpeech {
            return Color(red: 0.91, green: 0.39, blue: 0.10)  // #e8631a
        } else if isAlert {
            return Color(red: 0.10, green: 0.43, blue: 0.91)  // #1a6ee8
        } else {
            return Color(red: 0.53, green: 0.52, blue: 0.50).opacity(0.7)
        }
    }
}

// MARK: - SoundDirection

struct SoundDirection: Codable, Hashable, Equatable {
    /// Angle in radians: 0 = front, π/2 = right, π = behind, -π/2 = left
    let angle: Double
    let confidence: Float

    init(angle: Double, confidence: Float) {
        self.angle = angle
        self.confidence = confidence
    }

    var humanReadable: String {
        let normalized = angle.truncatingRemainder(dividingBy: 2 * .pi)
        let a = normalized < -.pi
            ? normalized + 2 * .pi
            : (normalized > .pi ? normalized - 2 * .pi : normalized)

        switch a {
        case -0.4..<0.4:               return "Ahead"
        case 0.4..<1.2:                return "Front-Right"
        case 1.2..<2.0:                return "Right"
        case 2.0..<2.7:                return "Back-Right"
        case 2.7...(.pi + 0.01):       return "Behind"
        case -(.pi)...(-2.7):          return "Behind"
        case -2.7..<(-2.0):            return "Back-Left"
        case -2.0..<(-1.2):            return "Left"
        case -1.2..<(-0.4):            return "Front-Left"
        default:                       return "Nearby"
        }
    }
}

// MARK: - SoundDetection

struct SoundDetection: Identifiable, Equatable {
    let id: UUID
    let soundType: SoundType
    let confidence: Float
    let timestamp: Date
    var direction: SoundDirection?
    var escalatedConfidence: Float
    var isVisible: Bool

    init(soundType: SoundType,
         confidence: Float,
         timestamp: Date,
         direction: SoundDirection? = nil,
         escalatedConfidence: Float? = nil,
         isVisible: Bool = true) {
        self.id = UUID()
        self.soundType = soundType
        self.confidence = confidence
        self.timestamp = timestamp
        self.direction = direction
        self.escalatedConfidence = escalatedConfidence ?? confidence
        self.isVisible = isVisible
    }

    /// Alias used in places where `.type` reads more naturally.
    var type: SoundType { soundType }
}
