// CoreMLSoundClassifier.swift
// =============================================================================
// PRIVACY BANNER — NO NETWORKING IN THE AUDIO PATH.
// The model runs entirely on-device (Neural Engine). No I/O beyond loading the
// bundled model file.
// =============================================================================
//
// Real `SoundClassifier` backed by a Core ML model on the Neural Engine
// (`computeUnits = .all`). Targets a YAMNet-class model (521 labels) by default
// but is model-agnostic: input/output feature names, the analysis window, and
// the input representation are all configurable so AST/BEATs can be swapped in.
//
// IMPORTANT: this initializer is FAILABLE. If the `.mlmodelc` is not present in
// the bundle (the common case until someone follows MODEL_SETUP.md), it returns
// nil and the factory falls back to `FakeSoundClassifier` — the app keeps
// working, we just don't stall on model acquisition.
//
// An `actor` so the non-Sendable `MLModel` stays isolated under Swift 6 strict
// concurrency.

import Foundation
import CoreML
import Accelerate

actor CoreMLSoundClassifier: SoundClassifying {

    /// How audio is presented to the model.
    enum InputMode {
        /// Raw 16 kHz waveform (the common Apple-converted YAMNet input; the
        /// model computes its own mel front-end).
        case waveform
    }

    private let model: MLModel
    private let labels: [String]
    private let inputName: String
    private let outputName: String
    private let modelSampleRate: Double
    private let windowLength: Int
    private let topK: Int

    /// - Parameters:
    ///   - modelName: base name of the compiled `.mlmodelc` in the bundle.
    ///   - labelsResource: newline-delimited labels file (521 lines for YAMNet).
    ///   - inputName/outputName: model feature names (adjust per model).
    init?(modelName: String = "YAMNet",
          labelsResource: String = "yamnet_labels",
          inputName: String = "waveform",
          outputName: String = "scores",
          modelSampleRate: Double = 16_000,
          windowSeconds: Double = 0.96,
          topK: Int = 5) {

        guard let url = Bundle.main.url(forResource: modelName, withExtension: "mlmodelc") else {
            return nil   // no model in bundle -> caller uses the fake
        }
        let config = MLModelConfiguration()
        config.computeUnits = .all   // prefer the Neural Engine
        guard let loaded = try? MLModel(contentsOf: url, configuration: config) else {
            return nil
        }

        self.model = loaded
        self.inputName = inputName
        self.outputName = outputName
        self.modelSampleRate = modelSampleRate
        self.windowLength = Int(windowSeconds * modelSampleRate)
        self.topK = topK

        // Labels are optional; without them we emit "class N".
        if let labelsURL = Bundle.main.url(forResource: labelsResource, withExtension: "txt"),
           let text = try? String(contentsOf: labelsURL, encoding: .utf8) {
            self.labels = text.split(whereSeparator: \.isNewline).map(String.init)
        } else {
            self.labels = []
        }
    }

    // MARK: - SoundClassifier

    func classify(_ buffer: AudioBuffer) async -> [ClassificationResult] {
        let mono = buffer.monoMix()
        guard !mono.isEmpty else { return [] }

        // Resample to the model's rate and fit to exactly one analysis window.
        let resampled = resample(mono, from: buffer.sampleRate, to: modelSampleRate)
        let frame = fitToWindow(resampled)

        guard let scores = runModel(on: frame) else { return [] }
        return topResults(from: scores)
    }

    // MARK: - Inference

    private func runModel(on frame: [Float]) -> [Float]? {
        guard let array = try? MLMultiArray(shape: [NSNumber(value: frame.count)],
                                            dataType: .float32) else { return nil }
        frame.withUnsafeBufferPointer { src in
            let dst = array.dataPointer.assumingMemoryBound(to: Float.self)
            dst.update(from: src.baseAddress!, count: frame.count)
        }

        let value = MLFeatureValue(multiArray: array)
        guard
            let provider = try? MLDictionaryFeatureProvider(dictionary: [inputName: value]),
            let output = try? model.prediction(from: provider),
            let scores = output.featureValue(for: outputName)?.multiArrayValue
        else { return nil }

        return meanScores(scores)
    }

    /// Flattens the score array, averaging across a leading frame dimension if
    /// the model emits per-hop scores.
    private func meanScores(_ array: MLMultiArray) -> [Float] {
        let total = array.count
        let ptr = array.dataPointer.assumingMemoryBound(to: Float.self)
        let flat = Array(UnsafeBufferPointer(start: ptr, count: total))

        let labelCount = labels.isEmpty ? total : labels.count
        guard labelCount > 0, total % labelCount == 0, total > labelCount else {
            return flat
        }
        let frames = total / labelCount
        var mean = [Float](repeating: 0, count: labelCount)
        for f in 0..<frames {
            for c in 0..<labelCount { mean[c] += flat[f * labelCount + c] }
        }
        let scale = 1 / Float(frames)
        for c in 0..<labelCount { mean[c] *= scale }
        return mean
    }

    private func topResults(from scores: [Float]) -> [ClassificationResult] {
        let ranked = scores.enumerated()
            .sorted { $0.element > $1.element }
            .prefix(topK)

        return ranked.map { index, score in
            let label = index < labels.count ? labels[index] : "class \(index)"
            return ClassificationResult(
                label: label,
                category: SoundLabelCatalog.category(for: label),
                confidence: score,
                isSpeech: SoundLabelCatalog.isSpeech(label)
            )
        }
    }

    // MARK: - Preprocessing

    /// Pads with zeros or takes the most recent window so the frame is exactly
    /// `windowLength` samples.
    private func fitToWindow(_ x: [Float]) -> [Float] {
        if x.count == windowLength { return x }
        if x.count > windowLength { return Array(x.suffix(windowLength)) }
        return x + [Float](repeating: 0, count: windowLength - x.count)
    }

    /// Simple linear-interpolation resampler (dependency-free). Adequate for a
    /// classifier front-end; not audiophile quality.
    private func resample(_ x: [Float], from inRate: Double, to outRate: Double) -> [Float] {
        guard inRate != outRate, !x.isEmpty else { return x }
        let ratio = outRate / inRate
        let outCount = Int((Double(x.count) * ratio).rounded())
        guard outCount > 1 else { return x }

        var out = [Float](repeating: 0, count: outCount)
        let step = inRate / outRate
        for i in 0..<outCount {
            let pos = Double(i) * step
            let i0 = Int(pos)
            let frac = Float(pos - Double(i0))
            let s0 = x[min(i0, x.count - 1)]
            let s1 = x[min(i0 + 1, x.count - 1)]
            out[i] = s0 + (s1 - s0) * frac
        }
        return out
    }
}
