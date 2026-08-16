// PowerModeOrchestrator.swift
// =============================================================================
// PRIVACY BANNER — NO NETWORKING IN THE AUDIO PATH.
// Audio stays in-memory: captured buffers are analysed and discarded; only the
// resulting RadarEvents (label/bearing/proximity) are retained.
// =============================================================================
//
// Feature 2 — Power Mode. Burst-oriented high-fidelity analysis:
//   • tap the toggle -> ~10 s window of stereo capture -> populate the radar ->
//     wind back down. Can also be left running while foregrounded.
//
// Pipeline per analysis window (~0.96 s, non-overlapping):
//   capture buffers -> accumulate a window -> classify + direction + proximity
//   -> RadarEvent -> publish to `events` (which the radar renders).
//
// Heavy DSP / Core ML runs OFF the main actor (`analyze` is nonisolated); only
// the light accumulation and the final publish touch main-actor state.

import Foundation
import Observation
import AVFoundation

@MainActor
@Observable
final class PowerModeOrchestrator {

    enum State: Equatable {
        case idle
        case running
        case permissionDenied
        case error(String)
    }

    // MARK: Published state

    private(set) var events: [RadarEvent] = []
    private(set) var state: State = .idle
    /// True stereo capture active (direction available). Mono => no bearings.
    private(set) var isStereo = false

    var isRunning: Bool { state == .running }
    /// Whether classification is the placeholder fake (drives a UI hint).
    var usingPlaceholderModel: Bool { !SoundClassifierFactory.hasBundledModel }

    // MARK: Configuration

    /// Analysis window length; matches the classifier's ~0.96 s hop.
    private let windowSeconds: Double = 0.96
    /// Minimum top-label confidence to emit an event.
    private let minConfidence: Float = 0.3
    /// Cap on retained events (the map decays them visually regardless).
    private let maxEvents = 100

    // MARK: Dependencies (swappable / testable)

    private let source: any AudioSource
    private let direction: any DirectionEstimator
    private let proximity: any ProximityEstimator
    private let classifier: any SoundClassifying

    // MARK: Private state

    private var consumeTask: Task<Void, Never>?
    private var burstTask: Task<Void, Never>?
    private var pending: [[Float]] = []
    private var pendingSampleRate: Double = 48_000

    init(source: any AudioSource = StereoAudioCapture(),
         direction: any DirectionEstimator = GCCPHATDirectionEstimator(),
         proximity: any ProximityEstimator = OnsetProximityEstimator(),
         classifier: (any SoundClassifying)? = nil) {
        self.source = source
        self.direction = direction
        self.proximity = proximity
        self.classifier = classifier ?? SoundClassifierFactory.make()
    }

    // MARK: - Control

    /// Fires a fixed-length burst, then winds down automatically.
    func startBurst(duration: TimeInterval = 10) async {
        guard await begin() else { return }
        burstTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            await self?.stop()
        }
    }

    /// Runs until `stop()`; use while the app is foregrounded.
    func startContinuous() async {
        _ = await begin()
    }

    func stop() async {
        burstTask?.cancel(); burstTask = nil
        consumeTask?.cancel(); consumeTask = nil
        await source.stop()
        pending.removeAll()
        if state == .running { state = .idle }
    }

    func clearEvents() { events.removeAll() }

    // MARK: - Startup

    private func begin() async -> Bool {
        guard state != .running else { return false }
        guard await requestMicPermission() else {
            state = .permissionDenied
            return false
        }
        do {
            let stream = try await source.start()
            isStereo = await source.isStereo
            state = .running
            DangerHaptics.prepare()
            consume(stream)
            return true
        } catch {
            state = .error(error.localizedDescription)
            return false
        }
    }

    private func requestMicPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    // MARK: - Consumption

    private func consume(_ stream: AsyncStream<AudioBuffer>) {
        consumeTask = Task { [weak self] in
            guard let self else { return }
            for await buffer in stream {
                guard let window = self.accumulate(buffer) else { continue }
                let event = await Self.analyze(
                    window,
                    direction: self.direction,
                    proximity: self.proximity,
                    classifier: self.classifier,
                    isStereo: self.isStereo,
                    minConfidence: self.minConfidence)
                if let event { self.publish(event) }
            }
        }
    }

    /// Appends samples and, once a full window is buffered, returns it and keeps
    /// the remainder. Runs on the main actor (cheap array work only).
    private func accumulate(_ buffer: AudioBuffer) -> AudioBuffer? {
        if pending.count != buffer.channelCount {
            pending = Array(repeating: [], count: buffer.channelCount)
            pendingSampleRate = buffer.sampleRate
        }
        for c in 0..<buffer.channelCount {
            pending[c].append(contentsOf: buffer.channels[c])
        }

        let need = Int(windowSeconds * pendingSampleRate)
        guard let first = pending.first, first.count >= need else { return nil }

        var windowChannels: [[Float]] = []
        windowChannels.reserveCapacity(pending.count)
        for c in 0..<pending.count {
            windowChannels.append(Array(pending[c].prefix(need)))
            pending[c].removeFirst(need)
        }
        return AudioBuffer(channels: windowChannels,
                           sampleRate: pendingSampleRate,
                           frameCount: need,
                           captureTime: Date(),
                           sampleTime: 0)
    }

    private func publish(_ event: RadarEvent) {
        events.append(event)
        if events.count > maxEvents {
            events.removeFirst(events.count - maxEvents)
        }
        // Feature 5: strong haptic on danger-tier detections.
        if event.isDanger { DangerHaptics.fire(for: event.dangerTier) }
    }

    // MARK: - Analysis (off main actor)

    private nonisolated static func analyze(_ window: AudioBuffer,
                                            direction: any DirectionEstimator,
                                            proximity: any ProximityEstimator,
                                            classifier: any SoundClassifying,
                                            isStereo: Bool,
                                            minConfidence: Float) async -> RadarEvent? {
        let results = await classifier.classify(window)
        guard let top = results.first, top.confidence >= minConfidence else { return nil }

        // Direction only when we actually have stereo — never a fake bearing.
        let bearing = isStereo ? direction.estimateBearing(window) : nil
        let prox = proximity.estimateProximity(window)

        return RadarEvent(timestamp: window.captureTime,
                          label: top.label,
                          category: top.category,
                          confidence: top.confidence,
                          bearing: bearing,
                          proximity: prox,
                          transcript: nil) // transcription wired in a later step
    }
}
