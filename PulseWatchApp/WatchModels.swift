// WatchModels.swift
// Self-contained models for the watch app. These intentionally do NOT import the
// iOS SoundModels — that file depends on the phone's PulseTheme/UI layer. Instead
// the watch mirrors the small subset it needs, keyed off the same rawValue strings
// that WatchConnectivityManager sends over WCSession.

import Foundation
import SwiftUI

// MARK: - WatchSoundType

/// Mirror of the phone's `SoundType`. Raw values MUST match the iOS enum so the
/// dictionary payload decodes cleanly.
enum WatchSoundType: String, CaseIterable {
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

    /// A wrist-legible accent color per category. Danger is always red.
    var accentColor: Color {
        switch self {
        case .siren, .fireAlarm, .explosion, .crash, .glassBreaking, .aggressiveYelling:
            return Color(red: 0.94, green: 0.26, blue: 0.25)   // alarm red
        case .carHorn, .trafficNoise:
            return Color(red: 0.94, green: 0.57, blue: 0.10)   // vehicle amber
        case .doorbell, .knocking, .phoneRinging:
            return Color(red: 0.09, green: 0.66, blue: 0.55)   // doorbell teal
        case .babyCrying:
            return Color(red: 0.94, green: 0.35, blue: 0.61)   // baby pink
        case .dogBarking, .musicPlaying:
            return Color(red: 0.52, green: 0.40, blue: 0.95)   // animal purple
        case .nearbyConversation, .nameDetected:
            return Color(red: 0.30, green: 0.68, blue: 0.98)   // speech blue
        }
    }
}

// MARK: - WatchDirection

struct WatchDirection: Equatable {
    /// Angle in radians: 0 = front, π/2 = right, π = behind, -π/2 = left.
    let angle: Double
    let confidence: Float

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

    /// Rotation (radians) for a "chevron up = ahead" arrow glyph.
    var arrowRotation: Angle { .radians(angle) }
}

// MARK: - WatchDetection

struct WatchDetection: Identifiable, Equatable {
    let id = UUID()
    let type: WatchSoundType
    let confidence: Float
    let direction: WatchDirection?
    let timestamp: Date

    /// Decodes the dictionary payload sent by the phone's WatchConnectivityManager.
    init?(payload: [String: Any]) {
        guard let raw = payload["soundType"] as? String,
              let type = WatchSoundType(rawValue: raw) else { return nil }
        self.type = type
        self.confidence = (payload["confidence"] as? NSNumber)?.floatValue ?? 0
        self.direction = WatchDetection.decodeDirection(from: payload)
        let ts = (payload["timestamp"] as? NSNumber)?.doubleValue
        self.timestamp = ts.map { Date(timeIntervalSince1970: $0) } ?? Date()
    }

    static func decodeDirection(from payload: [String: Any]) -> WatchDirection? {
        guard let angle = (payload["directionAngle"] as? NSNumber)?.doubleValue,
              angle.isFinite else { return nil }
        let conf = (payload["directionConfidence"] as? NSNumber)?.floatValue ?? 0
        return WatchDirection(angle: angle, confidence: conf)
    }
}

// MARK: - WatchTranscript

struct WatchTranscript: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let confidence: Float
    let timestamp: Date

    init?(payload: [String: Any]) {
        guard let text = payload["text"] as? String, !text.isEmpty else { return nil }
        self.text = text
        self.confidence = (payload["confidence"] as? NSNumber)?.floatValue ?? 0
        let ts = (payload["timestamp"] as? NSNumber)?.doubleValue
        self.timestamp = ts.map { Date(timeIntervalSince1970: $0) } ?? Date()
    }
}
