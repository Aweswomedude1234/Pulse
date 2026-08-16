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

    /// Maps a SoundAnalysis (SNClassifySoundRequest.version1) label identifier to a
    /// Pulse category. The v1 label set uses identifiers like "smoke_detector",
    /// "car_horn", "dog_bark"; we match on substrings to stay robust across SDKs.
    init?(snLabel: String) {
        let l = snLabel.lowercased()
        func has(_ s: String) -> Bool { l.contains(s) }
        switch true {
        case has("smoke"), has("fire_alarm"), has("fire alarm"), has("alarm"):
            self = .fireAlarm
        case has("siren"), has("emergency"):
            self = .siren
        case has("glass"), has("shatter"):
            self = .glassBreaking
        case has("explosion"), has("boom"):
            self = .explosion
        case has("horn"):
            self = .carHorn
        case has("doorbell"), has("ding_dong"):
            self = .doorbell
        case has("knock"):
            self = .knocking
        case has("telephone"), has("ringtone"), has("phone_ring"):
            self = .phoneRinging
        case has("baby"), has("infant"), has("cry"):
            self = .babyCrying
        case has("dog"), has("bark"):
            self = .dogBarking
        case has("shout"), has("yell"), has("scream"):
            self = .aggressiveYelling
        case has("traffic"):
            self = .trafficNoise
        case has("music"):
            self = .musicPlaying
        case has("speech"), has("conversation"), has("talk"):
            self = .nearbyConversation
        default:
            return nil
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
            return Color(hex: "#1E4235")   // catSmoke — alarm (dark shade)
        case .carHorn, .trafficNoise:
            return Color(hex: "#F0921B")   // catCar — vehicle amber
        case .doorbell, .knocking, .phoneRinging:
            return Color(hex: "#16A88B")   // catDoor — doorbell teal
        case .babyCrying:
            return Color(hex: "#F0589B")   // catBaby — baby pink
        case .dogBarking, .musicPlaying:
            return Color(hex: "#5AC7A0")   // catDog — animal (teal)
        case .nearbyConversation, .nameDetected:
            return Color(hex: "#22B573")   // catSpeech / accent — brand green
        }
    }
}

// MARK: - Color(hex:)
// Self-contained hex initializer mirroring the phone's PulseTheme extension so the
// watch reuses the exact same brand hex strings without importing the UI layer.

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB,
                  red:   Double(r) / 255,
                  green: Double(g) / 255,
                  blue:  Double(b) / 255,
                  opacity: Double(a) / 255)
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

/// Where a detection came from: mirrored from the phone, or heard on the watch.
enum DetectionSource: Equatable {
    case phone
    case watch
}

struct WatchDetection: Identifiable, Equatable {
    let id = UUID()
    let type: WatchSoundType
    let confidence: Float
    let direction: WatchDirection?
    let timestamp: Date
    let source: DetectionSource

    /// Decodes the dictionary payload sent by the phone's WatchConnectivityManager.
    init?(payload: [String: Any]) {
        guard let raw = payload["soundType"] as? String,
              let type = WatchSoundType(rawValue: raw) else { return nil }
        self.type = type
        self.confidence = (payload["confidence"] as? NSNumber)?.floatValue ?? 0
        self.direction = WatchDetection.decodeDirection(from: payload)
        let ts = (payload["timestamp"] as? NSNumber)?.doubleValue
        self.timestamp = ts.map { Date(timeIntervalSince1970: $0) } ?? Date()
        self.source = .phone
    }

    static func decodeDirection(from payload: [String: Any]) -> WatchDirection? {
        guard let angle = (payload["directionAngle"] as? NSNumber)?.doubleValue,
              angle.isFinite else { return nil }
        let conf = (payload["directionConfidence"] as? NSNumber)?.floatValue ?? 0
        return WatchDirection(angle: angle, confidence: conf)
    }

    /// General initializer used by the on-watch listening engine (and previews).
    init(type: WatchSoundType,
         confidence: Float,
         direction: WatchDirection? = nil,
         timestamp: Date = Date(),
         source: DetectionSource = .phone) {
        self.type = type
        self.confidence = confidence
        self.direction = direction
        self.timestamp = timestamp
        self.source = source
    }

    #if DEBUG
    /// Sample detection for previews / simulator UI checks.
    init(preview type: WatchSoundType,
         confidence: Float = 0.9,
         direction: WatchDirection? = nil,
         secondsAgo: TimeInterval = 0,
         source: DetectionSource = .phone) {
        self.init(type: type,
                  confidence: confidence,
                  direction: direction,
                  timestamp: Date().addingTimeInterval(-secondsAgo),
                  source: source)
    }
    #endif
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

    #if DEBUG
    /// Sample transcript for previews / simulator UI checks.
    init(preview text: String, confidence: Float = 0.9, secondsAgo: TimeInterval = 0) {
        self.text = text
        self.confidence = confidence
        self.timestamp = Date().addingTimeInterval(-secondsAgo)
    }
    #endif
}
