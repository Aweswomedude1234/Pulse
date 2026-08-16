// RadarGeometry.swift
// =============================================================================
// Pure geometry for the radar map — no SwiftUI View state, so it can be reasoned
// about and unit-tested independently.
//
// Screen-angle convention: 0 = straight up (device "ahead"), increasing
// CLOCKWISE, matching the direction estimator's bearing (0 = ahead, +right).
// A point at screen angle θ and radius r is  (cx + r·sinθ, cy − r·cosθ).
// =============================================================================

import SwiftUI

enum RadarGeometry {

    /// Fractional ring radius for each proximity bucket (× the radar's max
    /// radius). `nil` proximity (e.g. direction-only events) sits on the mid
    /// ring.
    static func ringFraction(for bucket: ProximityBucket?) -> CGFloat {
        switch bucket {
        case .near: return 0.34
        case .mid:  return 0.62
        case .far:  return 0.90
        case nil:   return 0.62
        }
    }

    /// Converts a screen angle (radians, 0 = up, clockwise) + radius into a
    /// point around `center`.
    static func point(angle: Double, radius: CGFloat, center: CGPoint) -> CGPoint {
        CGPoint(x: center.x + radius * CGFloat(sin(angle)),
                y: center.y - radius * CGFloat(cos(angle)))
    }

    /// Normalises an angle to (−π, π].
    static func normalize(_ angle: Double) -> Double {
        var a = angle.truncatingRemainder(dividingBy: 2 * .pi)
        if a <= -.pi { a += 2 * .pi }
        if a >   .pi { a -= 2 * .pi }
        return a
    }

    /// Front/back mirror of a bearing (reflection across the left–right mic
    /// axis): keeps lateralisation, flips front↔back. 0 (ahead) → π (behind).
    static func frontBackMirror(of bearing: Double) -> Double {
        normalize(.pi - bearing)
    }

    /// Annular-sector ("wedge") path spanning `bearing ± halfWidth` between two
    /// radii. The angular width encodes bearing uncertainty. Sampled as line
    /// segments for robustness.
    static func wedgePath(center: CGPoint,
                          innerRadius: CGFloat,
                          outerRadius: CGFloat,
                          bearing: Double,
                          halfWidth: Double,
                          samples: Int = 16) -> Path {
        let start = bearing - halfWidth
        let end   = bearing + halfWidth
        let step  = (end - start) / Double(max(1, samples))

        var path = Path()
        // Outer arc, start → end.
        for i in 0...samples {
            let a = start + step * Double(i)
            let p = point(angle: a, radius: outerRadius, center: center)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        // Inner arc, end → start.
        for i in 0...samples {
            let a = end - step * Double(i)
            let p = point(angle: a, radius: innerRadius, center: center)
            path.addLine(to: p)
        }
        path.closeSubpath()
        return path
    }
}
