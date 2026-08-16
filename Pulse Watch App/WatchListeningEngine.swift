// WatchListeningEngine.swift
// On-watch fallback: captures the microphone and classifies environmental sounds
// locally with SoundAnalysis when the phone isn't reachable. watchOS only permits
// mic capture while the app is in the foreground, so this runs only then.
//
// The whole engine is gated behind `canImport(SoundAnalysis)` so the app still
// builds on any SDK that happens not to vend SoundAnalysis for watchOS.

import Foundation
import AVFoundation

#if canImport(SoundAnalysis)
import SoundAnalysis

@MainActor
final class WatchListeningEngine: ObservableObject {

    /// Fired on the main actor when a sound is classified with usable confidence.
    var onDetection: ((WatchSoundType, Float) -> Void)?

    @Published private(set) var isRunning = false
    @Published private(set) var permissionDenied = false

    private let audioEngine = AVAudioEngine()
    private let analysisQueue = DispatchQueue(label: "com.pulse.watch.analysis")
    private var analyzer: SNAudioStreamAnalyzer?
    private var request: SNClassifySoundRequest?
    private var observer: ClassificationObserver?

    // Debounce so one continuous sound doesn't spam the feed.
    private var lastFire: [WatchSoundType: Date] = [:]
    private let debounce: TimeInterval = 4

    func start() {
        guard !isRunning else { return }
        requestPermissionThenStart()
    }

    func stop() {
        guard isRunning else { return }
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        analyzer?.removeAllRequests()
        analyzer = nil
        request = nil
        observer = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        isRunning = false
    }

    // MARK: - Setup

    private func requestPermissionThenStart() {
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            Task { @MainActor in
                guard let self else { return }
                guard granted else { self.permissionDenied = true; return }
                self.permissionDenied = false
                self.beginCapture()
            }
        }
    }

    private func beginCapture() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try session.setActive(true, options: [])
        } catch {
            return
        }

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { return }

        let analyzer = SNAudioStreamAnalyzer(format: format)
        guard let request = try? SNClassifySoundRequest(classifierIdentifier: .version1) else {
            return
        }

        let observer = ClassificationObserver { [weak self] type, confidence in
            Task { @MainActor in self?.handle(type, confidence) }
        }
        do {
            try analyzer.add(request, withObserver: observer)
        } catch {
            return
        }

        // Capture locals so the real-time tap closure never touches the main actor.
        let queue = analysisQueue
        input.installTap(onBus: 0, bufferSize: 8192, format: format) { buffer, when in
            queue.async {
                analyzer.analyze(buffer, atAudioFramePosition: when.sampleTime)
            }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            return
        }

        self.analyzer = analyzer
        self.request = request
        self.observer = observer
        isRunning = true
    }

    private func handle(_ type: WatchSoundType, _ confidence: Float) {
        let now = Date()
        if let last = lastFire[type], now.timeIntervalSince(last) < debounce { return }
        lastFire[type] = now
        onDetection?(type, confidence)
    }
}

// MARK: - SNResultsObserving

/// Standalone (non-MainActor) observer so it can satisfy the nonisolated
/// SNResultsObserving requirements regardless of the module's default isolation.
private final class ClassificationObserver: NSObject, SNResultsObserving {

    private let callback: (WatchSoundType, Float) -> Void
    private let minimumConfidence = 0.6

    init(callback: @escaping (WatchSoundType, Float) -> Void) {
        self.callback = callback
    }

    func request(_ request: any SNRequest, didProduce result: any SNResult) {
        guard let classification = result as? SNClassificationResult,
              let top = classification.classifications.first,
              top.confidence >= minimumConfidence,
              let type = WatchSoundType(snLabel: top.identifier) else { return }
        callback(type, Float(top.confidence))
    }
}

#else

// Stub used when SoundAnalysis is unavailable: the app still builds and the
// companion (phone-driven) path continues to work; only the on-watch fallback
// is disabled.
@MainActor
final class WatchListeningEngine: ObservableObject {
    var onDetection: ((WatchSoundType, Float) -> Void)?
    @Published private(set) var isRunning = false
    @Published private(set) var permissionDenied = false
    func start() {}
    func stop() {}
}

#endif
