// ExperimentConfig.swift
// Central, runtime-flippable configuration for A/B experiments and tiered-dispatch
// tuning. Introduced by change C0 so that later changes (C2 cascade, C4 danger
// recall, C5 thresholds, C6 voting, C7 custom classifier, C8 Whisper) can be
// toggled and compared on-device WITHOUT recompiling.
//
// Every default here reproduces the pre-change behavior, so wiring a consumer to
// ExperimentConfig is a no-op until an arm is explicitly flipped. Values persist
// in UserDefaults so an experiment survives relaunch.
//
// A/B tests to drive from here (see docs/change-list.md):
//   1. dangerRecall     — recall vs false-alarm rate for smoke/siren   (C4)
//   2. heavyClassifier  — custom EfficientNet vs Apple SNClassifySound v1 (C7)
//   3. transcription    — SFSpeech vs Whisper-tiny vs Whisper-base       (C8)
//   4. vad / cascade    — missed speech vs wasted inference              (C2)

import Foundation
import Combine

@MainActor
final class ExperimentConfig: ObservableObject {

    static let shared = ExperimentConfig()

    // MARK: - Arms

    /// C4 — how aggressively safety-critical sounds (smoke alarm, siren) fire.
    enum DangerRecall: String, CaseIterable {
        case conservative   // legacy behavior: danger needs a HIGH confidence bar
        case balanced       // danger bar == non-danger bar
        case aggressive     // danger fires on the lowest usable confidence (accept FPs)
    }

    /// C7 — which environmental-sound classifier is the source of truth.
    enum HeavyClassifier: String, CaseIterable {
        case appleV1            // SNClassifySoundRequest(.version1) only (legacy)
        case customEfficientNet // gated custom int8 EfficientNet (heavy tier)
        case both               // run custom as a confirmer on top of Apple (A/B)
    }

    /// C8 — transcription backend.
    enum Transcription: String, CaseIterable {
        case appleSFSpeech      // on-device SFSpeechRecognizer (legacy, single locale)
        case whisperTiny        // whisper.cpp ggml-tiny int8 (multilingual)
        case whisperBase        // whisper.cpp ggml-base int8 (multilingual)
    }

    // MARK: - Published knobs

    @Published var dangerRecall: DangerRecall {
        didSet { store(dangerRecall.rawValue, Keys.dangerRecall) }
    }
    @Published var heavyClassifier: HeavyClassifier {
        didSet { store(heavyClassifier.rawValue, Keys.heavyClassifier) }
    }
    @Published var transcription: Transcription {
        didSet { store(transcription.rawValue, Keys.transcription) }
    }

    /// C2 — gate SNAudioStreamAnalyzer behind the energy floor (skip inference when quiet).
    @Published var energyGateBeforeInference: Bool {
        didSet { store(energyGateBeforeInference, Keys.energyGate) }
    }
    /// C2 — number of consecutive speech windows required before starting ASR.
    @Published var vadSustainedWindows: Int {
        didSet { store(vadSustainedWindows, Keys.vadWindows) }
    }
    /// C6 — require agreement across N overlapping windows for non-safety classes.
    @Published var nonSafetyVotingWindows: Int {
        didSet { store(nonSafetyVotingWindows, Keys.voting) }
    }

    /// Master switch for the metrics/log overlay.
    @Published var metricsEnabled: Bool {
        didSet { store(metricsEnabled, Keys.metrics) }
    }

    // MARK: - Init (load or default)

    private init() {
        let d = UserDefaults.standard
        dangerRecall = DangerRecall(rawValue: d.string(forKey: Keys.dangerRecall) ?? "")
            ?? .conservative
        heavyClassifier = HeavyClassifier(rawValue: d.string(forKey: Keys.heavyClassifier) ?? "")
            ?? .appleV1
        transcription = Transcription(rawValue: d.string(forKey: Keys.transcription) ?? "")
            ?? .appleSFSpeech
        energyGateBeforeInference = d.object(forKey: Keys.energyGate) as? Bool ?? false
        vadSustainedWindows = d.object(forKey: Keys.vadWindows) as? Int ?? 1
        nonSafetyVotingWindows = d.object(forKey: Keys.voting) as? Int ?? 1
        metricsEnabled = d.object(forKey: Keys.metrics) as? Bool ?? false
    }

    // MARK: - Persistence

    private enum Keys {
        static let dangerRecall    = "exp.dangerRecall"
        static let heavyClassifier = "exp.heavyClassifier"
        static let transcription   = "exp.transcription"
        static let energyGate      = "exp.energyGateBeforeInference"
        static let vadWindows      = "exp.vadSustainedWindows"
        static let voting          = "exp.nonSafetyVotingWindows"
        static let metrics         = "exp.metricsEnabled"
    }

    private func store(_ value: Any, _ key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    /// Reset every arm to the legacy defaults (used by tests and the debug menu).
    func resetToDefaults() {
        dangerRecall = .conservative
        heavyClassifier = .appleV1
        transcription = .appleSFSpeech
        energyGateBeforeInference = false
        vadSustainedWindows = 1
        nonSafetyVotingWindows = 1
    }
}
