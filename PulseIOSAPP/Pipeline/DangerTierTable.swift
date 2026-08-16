// DangerTierTable.swift
// =============================================================================
// Feature 5 — the SINGLE editable label→danger-tier table. All danger logic
// lives here, not scattered across the pipeline as conditionals. Edit `rules`
// to change what counts as dangerous and at what severity.
// =============================================================================

import SwiftUI

/// Priority tier for an event. Ordered by severity so callers can compare.
enum DangerTier: Int, Sendable, Comparable, CaseIterable {
    case none = 0
    case warning = 1     // attention-worthy: knock, doorbell, running water, baby
    case critical = 2    // life-safety: smoke/CO alarm, glass, siren, screaming

    static func < (lhs: DangerTier, rhs: DangerTier) -> Bool { lhs.rawValue < rhs.rawValue }

    var displayName: String {
        switch self {
        case .none:     return "Normal"
        case .warning:  return "Attention"
        case .critical: return "Danger"
        }
    }

    var accent: Color {
        switch self {
        case .none:     return .clear
        case .warning:  return .orange
        case .critical: return Color(hex: "#1E4235")
        }
    }

    var systemImageName: String {
        switch self {
        case .none:     return "checkmark.circle"
        case .warning:  return "exclamationmark.circle.fill"
        case .critical: return "exclamationmark.triangle.fill"
        }
    }
}

enum DangerTierTable {

    /// The editable mapping. Keywords are matched case-insensitively against the
    /// raw classifier label; first matching rule wins, so keep `.critical` rules
    /// above `.warning` ones where labels could overlap.
    static let rules: [(keywords: [String], tier: DangerTier)] = [
        // --- Critical: life-safety ---
        (["smoke detector", "smoke alarm", "carbon monoxide", "fire alarm", "smoke"], .critical),
        (["glass", "shatter", "smash", "breaking", "explosion", "gunshot"],           .critical),
        (["siren", "civil defense", "air horn", "emergency"],                         .critical),
        (["scream", "shout", "yell", "screaming"],                                    .critical),

        // --- Warning: attention-worthy ---
        (["knock", "door knock"],                                                     .warning),
        (["doorbell", "ding-dong", "buzzer"],                                         .warning),
        (["water", "tap", "faucet", "sink", "running water", "shower"],               .warning),
        (["baby", "infant", "baby cry", "crying"],                                    .warning),
    ]

    /// Resolves a raw classifier label to its tier (`.none` if no rule matches).
    static func tier(for label: String) -> DangerTier {
        let lower = label.lowercased()
        for rule in rules where rule.keywords.contains(where: { lower.contains($0) }) {
            return rule.tier
        }
        return .none
    }
}

// MARK: - RadarEvent danger classification

extension RadarEvent {
    /// Danger tier resolved from the editable table (label first).
    var dangerTier: DangerTier { DangerTierTable.tier(for: label) }

    /// Whether this event gets the persistent, top-layer danger treatment on the
    /// map and a haptic on detection.
    var isDanger: Bool { dangerTier != .none }
}
