// PulseNotifications.swift
// =============================================================================
// Local notifications only — used by Always-On mode to surface danger-tier
// events when the screen is off, and to tell the user if monitoring stopped.
// No remote/push anything.
// =============================================================================

import Foundation
import UserNotifications

@MainActor
enum PulseNotifications {

    /// Requests alert/sound authorization. Safe to call repeatedly.
    @discardableResult
    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Fires a local alert for a danger-tier event detected in Always-On mode.
    static func postDanger(_ event: SoundEvent) {
        let content = UNMutableNotificationContent()
        content.title = event.dangerTier == .critical ? "⚠️ Danger detected" : "Heads up"
        content.body = event.label
        content.sound = event.dangerTier == .critical ? .defaultCritical : .default
        content.interruptionLevel = event.dangerTier == .critical ? .critical : .active
        submit(content, id: "danger-\(event.id.uuidString)")
    }

    /// Tells the user monitoring is no longer running (interruption or the
    /// system terminating the app — it will NOT be relaunched automatically).
    static func postMonitoringStopped(reason: String) {
        let content = UNMutableNotificationContent()
        content.title = "Pulse monitoring stopped"
        content.body = reason + " Open Pulse to resume."
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        submit(content, id: "monitoring-stopped")
    }

    private static func submit(_ content: UNMutableNotificationContent, id: String) {
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
