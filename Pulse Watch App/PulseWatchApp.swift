// PulseWatchApp.swift
// Pulse — Apple Watch companion. Mirrors environmental sound detections and live
// captions from the paired iPhone and alerts the wearer with distinct haptics.

import SwiftUI

@main
struct PulseWatchApp: App {

    @StateObject private var session = WatchSessionManager()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(session)
        }
        .onChange(of: scenePhase) { _, phase in
            // On-watch listening may only run in the foreground.
            session.setForeground(phase == .active)
        }
    }
}
