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
        case .alarm:   return .red
        case .impact:  return .orange
        case .alert:   return .yellow
        case .water:   return .blue
        case .animal:  return .pink
        case .vehicle: return .mint
        case .ambient: return .purple
        case .other:   return .gray
        }
    }
}

extension SoundEvent {
    // -------------------------------------------------------------------------
    // PLACEHOLDER danger flag so the map can render danger-tier events
    // distinctly today. Feature 5 (step 8) replaces this with the single
    // editable label→tier table; the map reads only `isDanger`, so swapping the
    // implementation there won't touch this view.
    // -------------------------------------------------------------------------
    var isDanger: Bool {
        switch category {
        case .alarm, .impact: return true
        default:              return false
        }
    }
}
