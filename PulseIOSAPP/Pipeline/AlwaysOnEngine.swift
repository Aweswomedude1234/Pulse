// AlwaysOnEngine.swift
// =============================================================================
// PRIVACY BANNER — NO NETWORKING IN THE AUDIO PATH.
// Audio stays in an in-memory rolling window; only SoundEvents are retained.
// =============================================================================
//
// Feature 3 — Always-On Power Mode (BETA, settings-gated). Runs with the screen
// off via UIBackgroundModes: audio and a continuously active recording session.
//
// IMPORTANT operational notes (App Review + user expectations):
//   • The orange microphone indicator is PERSISTENT while this runs.
//   • Continuous background recording is subject to App Review scrutiny.
//   • If the system terminates the app, it will NOT be relaunched
//     automatically — we surface a "monitoring stopped" notification on
//     interruption so the user knows to reopen Pulse.
//
// DUTY CYCLING IS MANDATORY. Three-stage gate, heavy stages idle the vast
// majority of the time:
//   (a) cheap RMS + temporal-flux energy gate, every buffer (always on);
//   (b) on trigger, wake the light classifier on the rolling window;
//   (c) only on a confirmed event, run the heavy path (direction + proximity
//       + transcription), then enter a cool-down.
//
// The ThermalPowerGovernor can force this down: on .serious / Low Power it drops
// transcription and widens the duty cycle; on .critical it pins tier to Baseline
// and this engine suppresses stages (b)/(c) entirely.

import Foundation
import Observation
import AVFoundation

@MainActor
@Observable
final class AlwaysOnEngine {

    enum State: Equatable {
        case idle, running, permissionDenied, error(String)
    }

    /// Current stage, surfaced for UI / debugging.
    enum Stage: String { case idle, gating, classifying, throttled }

    // MARK: Published

    private(set) var state: State = .idle
    private(set) var stage: Stage = .idle
    private(set) var events: [SoundEvent] = []
    private(set) var policy: PowerPolicy = .full

    var isRunning: Bool { state == .running }

    // MARK: Configuration

    private let windowSeconds: Double = 0.96
    /// Energy-gate thresholds (stage a).
    private let rmsThreshold: Float = 0.02
    private let fluxThreshold: Float = 0.015
    /// Light-classifier confidence needed to promote to the heavy path (stage c).
    private let lightConfidence: Float = 0.4
    /// Base cool-down after a heavy run, before stage a can promote again.
    private let baseCooldown: TimeInterval = 1.5
    /// Short cool-down after a trigger that didn't confirm, to avoid re-waking
    /// the classifier every buffer.
    private let missCooldown: TimeInterval = 0.4
    private let maxEvents = 100

    // MARK: Dependencies

    private let source: any AudioSource
    private let direction: any DirectionEstimator
    private let proximity: any ProximityEstimator
    private let classifier: any SoundClassifier
    private let governor: ThermalPowerGovernor

    // MARK: Private state

    private var consumeTask: Task<Void, Never>?
    private var policyTask: Task<Void, Never>?
    private var rolling: [[Float]] = []
    private var rollingSampleRate: Double = 48_000
    private var lastGateRMS: Float = 0
    private var heavyCooldownUntil = Date.distantPast
    private var isStereo = false
    private var interruptionObserver: NSObjectProtocol?

    init(source: any AudioSource = StereoAudioCapture(),
         direction: any DirectionEstimator = GCCPHATDirectionEstimator(),
         proximity: any ProximityEstimator = OnsetProximityEstimator(),
         classifier: (any SoundClassifier)? = nil,
         governor: ThermalPowerGovernor = ThermalPowerGovernor()) {
        self.source = source
        self.direction = direction
        self.proximity = proximity
        self.classifier = classifier ?? SoundClassifierFactory.make()
        self.governor = governor
    }

    // MARK: - Control

    func start() async {
        guard state != .running else { return }
        guard await AVAudioApplication.requestRecordPermission() else {
            state = .permissionDenied; return
        }
        await PulseNotifications.requestAuthorization()

        _ = await governor.requestTier(.alwaysOn)
        policy = governor.policy
        observePolicy()
        observeInterruptions()

        do {
            let stream = try await source.start()
            isStereo = await source.isStereo
            state = .running
            stage = .gating
            DangerHaptics.prepare()
            consume(stream)
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    func stop() async {
        consumeTask?.cancel(); consumeTask = nil
        policyTask?.cancel(); policyTask = nil
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
            self.interruptionObserver = nil
        }
        await source.stop()
        _ = await governor.requestTier(.baseline)
        rolling.removeAll()
        stage = .idle
        if state == .running { state = .idle }
    }

    func clearEvents() { events.removeAll() }

    // MARK: - Governor

    private func observePolicy() {
        let stream = governor.policyChanges()
        policyTask = Task { [weak self] in
            for await newPolicy in stream {
                guard let self else { return }
                self.policy = newPolicy
            }
        }
    }

    // MARK: - Interruptions

    private func observeInterruptions() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil, queue: .main) { [weak self] note in
            Task { @MainActor in self?.handleInterruption(note) }
        }
    }

    private func handleInterruption(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        if type == .began {
            // Recording was interrupted; monitoring is no longer live.
            PulseNotifications.postMonitoringStopped(reason: "Audio was interrupted.")
        }
    }

    // MARK: - Consumption / duty cycle

    private func consume(_ stream: AsyncStream<AudioBuffer>) {
        consumeTask = Task { [weak self] in
            guard let self else { return }
            for await buffer in stream {
                // Stage (a): cheap energy gate, every buffer.
                self.appendRolling(buffer)
                guard self.passesEnergyGate(buffer) else { continue }

                let now = Date()
                guard now >= self.heavyCooldownUntil else { continue }

                // Governor forced Baseline (e.g. .critical thermal): suppress
                // heavy stages entirely.
                guard self.policy.tier != .baseline else {
                    self.stage = .throttled
                    continue
                }

                // Stages (b)+(c) off the main actor.
                self.stage = .classifying
                let window = self.snapshotWindow()
                let event = await Self.analyze(
                    window,
                    direction: self.direction,
                    proximity: self.proximity,
                    classifier: self.classifier,
                    isStereo: self.isStereo,
                    lightConfidence: self.lightConfidence,
                    transcriptionEnabled: self.policy.transcriptionEnabled)

                if let event {
                    self.publish(event)
                    self.heavyCooldownUntil = now + self.baseCooldown * self.policy.dutyCycleMultiplier
                } else {
                    self.heavyCooldownUntil = now + self.missCooldown
                }
                self.stage = .gating
            }
        }
    }

    // MARK: Stage (a)

    private func passesEnergyGate(_ buffer: AudioBuffer) -> Bool {
        let rms = bufferRMS(buffer)
        let flux = abs(rms - lastGateRMS)
        lastGateRMS = rms
        return rms > rmsThreshold || flux > fluxThreshold
    }

    private func bufferRMS(_ buffer: AudioBuffer) -> Float {
        let mono = buffer.channels.first ?? []
        guard !mono.isEmpty else { return 0 }
        var sum: Float = 0
        for s in mono { sum += s * s }
        return (sum / Float(mono.count)).squareRoot()
    }

    // MARK: Rolling window

    private func appendRolling(_ buffer: AudioBuffer) {
        if rolling.count != buffer.channelCount {
            rolling = Array(repeating: [], count: buffer.channelCount)
            rollingSampleRate = buffer.sampleRate
        }
        let cap = Int(windowSeconds * buffer.sampleRate)
        for c in 0..<buffer.channelCount {
            rolling[c].append(contentsOf: buffer.channels[c])
            if rolling[c].count > cap {
                rolling[c].removeFirst(rolling[c].count - cap)
            }
        }
    }

    private func snapshotWindow() -> AudioBuffer {
        let frames = rolling.first?.count ?? 0
        return AudioBuffer(channels: rolling,
                           sampleRate: rollingSampleRate,
                           frameCount: frames,
                           captureTime: Date(),
                           sampleTime: 0)
    }

    // MARK: Publish

    private func publish(_ event: SoundEvent) {
        events.append(event)
        if events.count > maxEvents { events.removeFirst(events.count - maxEvents) }
        if event.isDanger {
            DangerHaptics.fire(for: event.dangerTier)
            PulseNotifications.postDanger(event)
        }
    }

    // MARK: Stages (b)+(c), off main

    private nonisolated static func analyze(_ window: AudioBuffer,
                                            direction: any DirectionEstimator,
                                            proximity: any ProximityEstimator,
                                            classifier: any SoundClassifier,
                                            isStereo: Bool,
                                            lightConfidence: Float,
                                            transcriptionEnabled: Bool) async -> SoundEvent? {
        // Stage (b): light classifier.
        let results = await classifier.classify(window)
        guard let top = results.first, top.confidence >= lightConfidence else { return nil }

        // Stage (c): heavy path — direction + proximity (+ transcription later).
        let bearing = isStereo ? direction.estimateBearing(window) : nil
        let prox = proximity.estimateProximity(window)
        // transcriptionEnabled gates the (future) WhisperKit stage; nil for now.
        _ = transcriptionEnabled

        return SoundEvent(timestamp: window.captureTime,
                          label: top.label,
                          category: top.category,
                          confidence: top.confidence,
                          bearing: bearing,
                          proximity: prox,
                          transcript: nil)
    }
}
