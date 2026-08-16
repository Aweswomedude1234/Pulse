// FakeSoundClassifier.swift
// =============================================================================
// PRIVACY BANNER — NO NETWORKING IN THE AUDIO PATH.
// Pure on-device signal processing. No I/O.
// =============================================================================
//
// Deterministic placeholder `SoundClassifier` used until a real `.mlpackage` is
// dropped in (see MODEL_SETUP.md). It is NOT machine learning and makes no
// pretence of accuracy — it derives a stable, non-random label from cheap
// signal features (loudness + a zero-crossing "brightness" proxy) so the rest
// of the pipeline, the map, and tests all have something concrete to run on.
//
// Determinism is the whole point: identical input always yields identical
// output, so downstream code can be tested without a model.

import Foundation
import Accelerate

struct FakeSoundClassifier: SoundClassifying {

    /// Below this RMS we report "nothing heard" (empty result).
    let silenceRMS: Float

    init(silenceRMS: Float = 0.005) {
        self.silenceRMS = silenceRMS
    }

    func classify(_ buffer: AudioBuffer) async -> [ClassificationResult] {
        let samples = buffer.monoMix()
        guard samples.count > 1 else { return [] }

        let rms = rootMeanSquare(samples)
        guard rms > silenceRMS else { return [] }

        // Zero-crossing rate as a cheap brightness proxy (Hz-equivalent).
        let crossingRate = zeroCrossingRate(samples, sampleRate: buffer.sampleRate)

        // Map brightness to a plausible, deterministic label.
        let label: String
        switch crossingRate {
        case ..<800:        label = "Ambient noise"
        case 800..<2500:    label = "Speech"
        case 2500..<5000:   label = "Water, running"
        default:            label = "Alarm, high-pitched beep"
        }

        // Confidence scales with how far above the silence floor we are.
        let confidence = min(1, max(0, (rms - silenceRMS) / (0.2 - silenceRMS)))

        return [ClassificationResult(
            label: label,
            category: SoundLabelCatalog.category(for: label),
            confidence: confidence,
            isSpeech: SoundLabelCatalog.isSpeech(label)
        )]
    }

    // MARK: - Features

    private func rootMeanSquare(_ x: [Float]) -> Float {
        var ms: Float = 0
        vDSP_measqv(x, 1, &ms, vDSP_Length(x.count))
        return ms.squareRoot()
    }

    private func zeroCrossingRate(_ x: [Float], sampleRate: Double) -> Double {
        var crossings = 0
        for i in 1..<x.count where (x[i] >= 0) != (x[i - 1] >= 0) { crossings += 1 }
        let duration = Double(x.count) / sampleRate
        return duration > 0 ? Double(crossings) / duration : 0
    }
}
