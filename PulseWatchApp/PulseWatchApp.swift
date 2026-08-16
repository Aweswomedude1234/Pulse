// PulseWatchApp.swift
// Pulse — Apple Watch companion. Mirrors environmental sound detections and live
// captions from the paired iPhone and alerts the wearer with distinct haptics.

import SwiftUI

@main
struct PulseWatchApp: App {

    @StateObject private var session = WatchSessionManager()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(session)
        }
    }
}
