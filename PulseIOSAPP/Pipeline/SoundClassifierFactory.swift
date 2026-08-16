// SoundClassifierFactory.swift
// =============================================================================
// PRIVACY BANNER — NO NETWORKING IN THE AUDIO PATH.
// =============================================================================
//
// Single place that decides which `SoundClassifier` the pipeline uses. If a
// real Core ML model is bundled it wins; otherwise we transparently fall back
// to the deterministic fake so the app never stalls on model acquisition.

import Foundation

enum SoundClassifierFactory {

    /// Returns the best available classifier. Prefers the on-device Core ML
    /// model; falls back to `FakeSoundClassifier` when no model is bundled.
    static func make(modelName: String = "YAMNet") -> any SoundClassifying {
        if let coreML = CoreMLSoundClassifier(modelName: modelName) {
            return coreML
        }
        return FakeSoundClassifier()
    }

    /// Whether a real model is present (drives any "using placeholder" UI hint).
    static var hasBundledModel: Bool {
        Bundle.main.url(forResource: "YAMNet", withExtension: "mlmodelc") != nil
    }
}
