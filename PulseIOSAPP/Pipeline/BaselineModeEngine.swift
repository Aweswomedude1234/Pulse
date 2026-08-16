// BaselineModeEngine.swift
// =============================================================================
// PRIVACY BANNER — NO NETWORKING IN THE AUDIO PATH.
// SoundAnalysis and Speech both run on-device (speech forced on-device). Audio
// and transcripts never leave the phone.
// =============================================================================
//
// Feature 1 — Baseline Mode. The cheap, always-available default:
//   • SNAudioStreamAnalyzer + SNClassifySoundRequest (Apple's built-in
//     classifier) for coarse sound identification.
//   • SFSpeechRecognizer with requiresOnDeviceRecognition = true for live
//     transcription.
// No direction, no proximity — just a scrolling list of sounds and transcript
// text. Negligible battery impact; this is what runs when nothing else is on.

import Foundation
import Observation
import AVFoundation
import SoundAnalysis
import Speech

/// One coarse sound identification for the scrolling list.
struct BaselineDetection: Identifiable, Hashable {
    let id = UUID()
    let label: String
    let confidence: Float
    let timestamp: Date
}

@MainActor
@Observable
final class BaselineModeEngine {

    enum State: Equatable {
        case idle
        case running
        case permissionDenied
        case error(String)
    }

    // MARK: Published

    private(set) var state: State = .idle
    /// Newest-first list of identified sounds.
    private(set) var detections: [BaselineDetection] = []
    /// Finalized transcript lines, oldest-first.
    private(set) var transcriptLines: [String] = []
    /// Transcript of the utterance currently being spoken.
    private(set) var partialTranscript: String = ""

    var isRunning: Bool { state == .running }

    // MARK: Configuration

    /// Minimum classifier confidence to surface a sound.
    private let minConfidence: Double = 0.3
    /// Suppress repeats of the same label within this interval.
    private let dedupeInterval: TimeInterval = 2

    // MARK: Audio + analysis

    private let engine = AVAudioEngine()
    private let analysisQueue = DispatchQueue(label: "pulse.baseline.analysis")
    private var analyzer: SNAudioStreamAnalyzer?
    private var classifyRequest: SNClassifySoundRequest?
    private var observer: ClassificationObserver?

    // MARK: Speech

    private let recognizer = SFSpeechRecognizer()
    private var speechRequest: SFSpeechAudioBufferRecognitionRequest?
    private var speechTask: SFSpeechRecognitionTask?

    private var lastLabel: String?
    private var lastLabelTime = Date.distantPast

    // MARK: - Control

    func start() async {
        guard state != .running else { return }
        guard await requestPermissions() else {
            state = .permissionDenied
            return
        }
        do {
            try configureSession()
            try startAudioAndAnalysis()
            startSpeech()
            DangerHaptics.prepare()
            state = .running
        } catch {
            state = .error(error.localizedDescription)
            await stop()
        }
    }

    func stop() async {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        analyzer = nil
        classifyRequest = nil
        observer = nil
        speechTask?.cancel()
        speechTask = nil
        speechRequest?.endAudio()
        speechRequest = nil
        partialTranscript = ""
        if state == .running { state = .idle }

        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    func clear() {
        detections.removeAll()
        transcriptLines.removeAll()
        partialTranscript = ""
    }

    // MARK: - Permissions

    private func requestPermissions() async -> Bool {
        let mic = await AVAudioApplication.requestRecordPermission()
        guard mic else { return false }
        let speech = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        // Speech is optional — sound ID still works if it's denied — but we
        // require the mic.
        return speech == .authorized || speech == .denied || speech == .restricted
    }

    // MARK: - Session

    private func configureSession() throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        // Plain .record/.default — Baseline needs no phase fidelity, so no
        // .measurement mode (keeps normal input processing / low power).
        try session.setCategory(.record, mode: .default, options: [.duckOthers])
        try session.setActive(true, options: [])
        #endif
        // macOS has no audio session — the engine taps the system input device
        // directly, so there is nothing to configure here.
    }

    // MARK: - Sound analysis

    private func startAudioAndAnalysis() throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)

        let analyzer = SNAudioStreamAnalyzer(format: format)
        let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
        let observer = ClassificationObserver { [weak self] label, confidence in
            // `label`/`confidence` are Sendable value types — safe to hop.
            Task { @MainActor in self?.handle(label: label, confidence: confidence) }
        }
        try analyzer.add(request, withObserver: observer)

        self.analyzer = analyzer
        self.classifyRequest = request
        self.observer = observer

        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, when in
            guard let self else { return }
            // SoundAnalysis on its own queue; speech request appended directly.
            self.analysisQueue.async {
                self.analyzer?.analyze(buffer, atAudioFramePosition: when.sampleTime)
            }
            self.speechRequest?.append(buffer)
        }

        engine.prepare()
        try engine.start()
    }

    private func handle(label: String, confidence: Double) {
        guard confidence >= minConfidence else { return }
        let now = Date()
        if label == lastLabel, now.timeIntervalSince(lastLabelTime) < dedupeInterval { return }
        lastLabel = label
        lastLabelTime = now

        let pretty = prettify(label)
        detections.insert(
            BaselineDetection(label: pretty,
                              confidence: Float(confidence),
                              timestamp: now),
            at: 0)
        if detections.count > 100 { detections.removeLast(detections.count - 100) }

        // Feature 5: danger-tier sounds get a strong haptic even in Baseline.
        let tier = DangerTierTable.tier(for: label)
        if tier != .none { DangerHaptics.fire(for: tier) }
    }

    /// Turns SoundAnalysis identifiers ("smoke_detector_smoke_alarm") into a
    /// human label.
    private func prettify(_ identifier: String) -> String {
        identifier.replacingOccurrences(of: "_", with: " ").capitalized
    }

    // MARK: - Speech

    private func startSpeech() {
        guard let recognizer, recognizer.isAvailable else { return }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true   // hard requirement: on-device only
        speechRequest = request

        speechTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            // Extract Sendable values before hopping to the main actor.
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failed = error != nil
            Task { @MainActor in
                guard let self else { return }
                if let text, !failed {
                    if isFinal {
                        if !text.isEmpty { self.transcriptLines.append(text) }
                        self.partialTranscript = ""
                        self.restartSpeechIfRunning()
                    } else {
                        self.partialTranscript = text
                    }
                } else if failed {
                    self.partialTranscript = ""
                    self.restartSpeechIfRunning()
                }
            }
        }
    }

    /// On-device speech tasks finalize after silence; restart for a continuous
    /// baseline transcript while the mode stays on.
    private func restartSpeechIfRunning() {
        speechTask = nil
        speechRequest = nil
        guard state == .running else { return }
        startSpeech()
    }
}

// MARK: - SoundAnalysis observer

/// Bridges SNResultsObserving callbacks (delivered on the analysis queue) into a
/// closure. Must be an NSObject subclass to conform.
private final class ClassificationObserver: NSObject, SNResultsObserving {
    private let onResult: (String, Double) -> Void

    init(onResult: @escaping (String, Double) -> Void) {
        self.onResult = onResult
    }

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let classification = result as? SNClassificationResult,
              let top = classification.classifications.first else { return }
        // Extract Sendable values here, on the analysis queue.
        onResult(top.identifier, top.confidence)
    }
}
