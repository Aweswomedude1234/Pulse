// DangerHaptics.swift
// =============================================================================
// Feature 5 — strong haptic feedback on danger-tier detections. Critical events
// fire an error notification; warnings fire a warning notification.
// =============================================================================

#if canImport(UIKit)
import UIKit

@MainActor
enum DangerHaptics {
    private static let generator = UINotificationFeedbackGenerator()

    /// Warm up the Taptic Engine so the first alert isn't delayed.
    static func prepare() { generator.prepare() }

    static func fire(for tier: DangerTier) {
        switch tier {
        case .critical: generator.notificationOccurred(.error)
        case .warning:  generator.notificationOccurred(.warning)
        case .none:     break
        }
        generator.prepare() // ready for the next one
    }
}
#else
// Non-UIKit platforms: haptics are a no-op.
@MainActor
enum DangerHaptics {
    static func prepare() {}
    static func fire(for tier: DangerTier) {}
}
#endif
