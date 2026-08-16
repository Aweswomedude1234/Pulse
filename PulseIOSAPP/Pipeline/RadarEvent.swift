// RadarEvent.swift
// =============================================================================
// PRIVACY BANNER — NO NETWORKING IN THE AUDIO PATH.
// Events are the single model the radar map renders. They persist locally only.
// =============================================================================

import Foundation
import SwiftUI

// MARK: - SoundCategory

/// Coarse, app-facing grouping that classifier labels collapse into. Kept
/// intentionally small and stable; the raw model label is preserved separately
/// on `RadarEvent.label`. The danger-tier mapping (Feature 5) is a separate
/// editable table layered on top of this — categories here are neutral.
enum SoundCategory: String, Sendable, Codable, CaseIterable {
    case speech
    case alarm          // smoke/CO alarm, siren
    case impact         // glass breaking, crash, knock
    case alert          // doorbell, phone, appliance beeps
    case water          // running tap, shower
    case animal         // dog, cat, baby (biological callouts)
    case vehicle        // car horn, engine, traffic
    case ambient        // music, background, unclassified environment
    case other

    var displayName: String {
        switch self {
        case .speech:  return "Speech"
        case .alarm:   return "Alarm"
        case .impact:  return "Impact"
        case .alert:   return "Alert"
        case .water:   return "Water"
        case .animal:  return "Animal"
        case .vehicle: return "Vehicle"
        case .ambient: return "Ambient"
        case .other:   return "Sound"
        }
    }

    /// SF Symbol drawn inside the radar blip.
    var systemImageName: String {
        switch self {
        case .speech:  return "waveform"
        case .alarm:   return "bell.and.waves.left.and.right.fill"
        case .impact:  return "burst.fill"
        case .alert:   return "bell.fill"
        case .water:   return "drop.fill"
        case .animal:  return "pawprint.fill"
        case .vehicle: return "car.fill"
        case .ambient: return "music.note"
        case .other:   return "dot.radiowaves.left.and.right"
        }
    }
}

// MARK: - RadarEvent

/// The single record the map, feed, and history all render. Value type so it
/// crosses actor boundaries freely; persisted separately by the `EventStore`.
///
/// Bearing/proximity are optional: Baseline Mode produces events with neither,
/// and mono capture in Power Mode produces events with no bearing.
struct RadarEvent: Sendable, Identifiable, Hashable {
    let id: UUID
    let timestamp: Date

    /// Raw classifier label, preserved verbatim (e.g. YAMNet class string).
    let label: String
    /// Coarse category the label maps to.
    let category: SoundCategory
    /// Classification confidence in [0, 1].
    let confidence: Float

    /// Direction estimate, when Power Mode + stereo produced one. `nil` means
    /// "no direction available" — never a fabricated bearing.
    let bearing: BearingEstimate?
    /// Relative proximity bucket, when estimated. `nil` in Baseline Mode.
    let proximity: ProximityEstimate?

    /// Transcript excerpt for speech events, when available.
    let transcript: String?

    init(id: UUID = UUID(),
         timestamp: Date = Date(),
         label: String,
         category: SoundCategory,
         confidence: Float,
         bearing: BearingEstimate? = nil,
         proximity: ProximityEstimate? = nil,
         transcript: String? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.label = label
        self.category = category
        self.confidence = confidence
        self.bearing = bearing
        self.proximity = proximity
        self.transcript = transcript
    }

    /// Convenience: bearing uncertainty half-width in radians, or `nil`.
    var uncertainty: Double? { bearing?.uncertainty }

    /// Whether this event has usable directional information for the map.
    var hasDirection: Bool { bearing != nil }
}
