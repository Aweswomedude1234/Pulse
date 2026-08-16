// WatchSessionManager.swift
// Receives mirrored detections + transcription from the paired iPhone over
// WCSession, plays a wrist haptic per event, and publishes state for the UI.

import Foundation
import Combine
import WatchConnectivity
import WatchKit

@MainActor
final class WatchSessionManager: NSObject, ObservableObject {

    /// Which source is currently feeding detections.
    enum ActiveSource: Equatable {
        case phone      // companion is reachable; phone drives detection
        case watch      // on-watch listening (phone unreachable, app foreground)
        case idle       // not listening (phone unreachable, app not active)
    }

    @Published private(set) var latestDetection: WatchDetection?
    @Published private(set) var recentDetections: [WatchDetection] = []
    @Published private(set) var transcripts: [WatchTranscript] = []
    @Published private(set) var isReachable: Bool = false
    @Published private(set) var activeSource: ActiveSource = .idle
    @Published private(set) var micDenied: Bool = false

    private let session: WCSession? = WCSession.isSupported() ? WCSession.default : nil
    private let listening = WatchListeningEngine()
    private var isForeground = false
    private let maxDetections = 50
    private let maxTranscripts = 40

    override init() {
        super.init()
        listening.onDetection = { [weak self] type, confidence in
            guard let self else { return }
            self.apply(WatchDetection(type: type, confidence: confidence, source: .watch))
        }
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    // MARK: - Source coordination
    //
    // Companion when the phone is reachable; on-watch listening as a foreground
    // fallback when it isn't. watchOS only allows mic capture in the foreground,
    // so we also stop when the app leaves the foreground.

    /// Called by the app when the scene phase changes.
    func setForeground(_ foreground: Bool) {
        isForeground = foreground
        reconcileSource()
    }

    private func reconcileSource() {
        if isReachable {
            listening.stop()
            activeSource = .phone
        } else if isForeground {
            listening.start()
            activeSource = .watch
        } else {
            listening.stop()
            activeSource = .idle
        }
        micDenied = listening.permissionDenied
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
        Task { @MainActor in
            self.isReachable = reachable
            self.reconcileSource()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in
            self.isReachable = reachable
            self.reconcileSource()
        }
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

#if DEBUG
extension WatchSessionManager {
    /// A manager pre-seeded with sample data for SwiftUI previews / simulator UI
    /// checks without a paired phone. Same-file access lets us set private(set).
    static func previewPopulated() -> WatchSessionManager {
        let m = WatchSessionManager()
        let dets = [
            WatchDetection(preview: .fireAlarm,
                           direction: WatchDirection(angle: 0.9, confidence: 0.8)),
            WatchDetection(preview: .doorbell, secondsAgo: 45),
            WatchDetection(preview: .dogBarking, secondsAgo: 130),
            WatchDetection(preview: .nameDetected, secondsAgo: 210)
        ]
        m.recentDetections = dets
        m.latestDetection = dets.first
        m.transcripts = [
            WatchTranscript(preview: "Hey, are you coming to dinner?"),
            WatchTranscript(preview: "The package just arrived.", secondsAgo: 30)
        ]
        m.isReachable = true
        m.activeSource = .phone
        return m
    }
}
#endif
