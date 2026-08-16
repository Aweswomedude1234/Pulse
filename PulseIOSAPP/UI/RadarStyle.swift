// RadarStyle.swift
// =============================================================================
// Visual styling for the radar map: per-category tint and the (placeholder)
// danger-tier flag the map uses for its top-layer treatment.
// =============================================================================

import SwiftUI

extension SoundCategory {
    /// Blip tint on the radar.
    var tint: Color {
        switch self {
        case .speech:  return .cyan
        case .alarm:   return Color(hex: "#1E4235")
        case .impact:  return .orange
        case .alert:   return .yellow
        case .water:   return .blue
        case .animal:  return .pink
        case .vehicle: return .mint
        case .ambient: return Color(hex: "#5AC7A0")
        case .other:   return .gray
        }
    }
}

// `RadarEvent.isDanger` / `.dangerTier` now come from the editable
// `DangerTierTable` (Feature 5). The map reads only those, so nothing here
// needs to know the mapping.
