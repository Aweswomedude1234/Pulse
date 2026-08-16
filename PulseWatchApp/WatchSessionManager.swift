// WatchSessionManager.swift
// Receives mirrored detections + transcription from the paired iPhone over
// WCSession, plays a wrist haptic per event, and publishes state for the UI.

import Foundation
import Combine
import WatchConnectivity
import WatchKit

@MainActor
final class WatchSessionManager: NSObject, ObservableObject {

    @Published private(set) var latestDetection: WatchDetection?
    @Published private(set) var recentDetections: [WatchDetection] = []
    @Published private(set) var transcripts: [WatchTranscript] = []
    @Published private(set) var isReachable: Bool = false

    private let session: WCSession? = WCSession.isSupported() ? WCSession.default : nil
    private let maxDetections = 50
    private let maxTranscripts = 40

    override init() {
        super.init()
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    // MARK: - Ingest (called on the main actor)

    fileprivate func ingest(payload: [String: Any]) {
        switch payload["kind"] as? String {
        case "detection":
            guard let detection = WatchDetection(payload: payload) else { return }
            apply(detection)
        case "transcription":
            guard let line = WatchTranscript(payload: payload) else { return }
            transcripts.insert(line, at: 0)
            if transcripts.count > maxTranscripts {
                transcripts = Array(transcripts.prefix(maxTranscripts))
            }
        default:
            break
        }
    }

    private func apply(_ detection: WatchDetection) {
        latestDetection = detection
        recentDetections.insert(detection, at: 0)
        if recentDetections.count > maxDetections {
            recentDetections = Array(recentDetections.prefix(maxDetections))
        }
        play(for: detection.type)
    }

    /// Distinct haptic vocabulary so the wrist alone conveys severity:
    /// danger → repeated notification, alert → notification, speech → click.
    private func play(for type: WatchSoundType) {
        let device = WKInterfaceDevice.current()
        if type.isDangerous {
            device.play(.notification)
            // A second pulse shortly after makes danger unmistakable. The system
            // enforces a ~100 ms minimum gap between haptics, so 0.35 s is safe.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                device.play(.notification)
            }
        } else if type.isAlert {
            device.play(.notification)
        } else {
            device.play(.click)
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchSessionManager: WCSessionDelegate {

    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        let reachable = session.isReachable
        Task { @MainActor in self.isReachable = reachable }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in self.isReachable = reachable }
    }

    // Live path: phone is reachable and sends the event immediately.
    nonisolated func session(_ session: WCSession,
                             didReceiveMessage message: [String: Any]) {
        Task { @MainActor in self.ingest(payload: message) }
    }

    // Queued path: phone used transferUserInfo while the watch was asleep.
    nonisolated func session(_ session: WCSession,
                             didReceiveUserInfo userInfo: [String: Any]) {
        Task { @MainActor in self.ingest(payload: userInfo) }
    }
}
