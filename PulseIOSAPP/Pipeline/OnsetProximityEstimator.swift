// OnsetProximityEstimator.swift
// =============================================================================
// PRIVACY BANNER — NO NETWORKING IN THE AUDIO PATH.
// Pure on-device signal processing. No I/O of any kind.
// =============================================================================
//
// Relative proximity estimation. THERE IS NO TRUE DISTANCE MEASUREMENT HERE — we
// output a coarse bucket (.near / .mid / .far) with a confidence, and it must
// never be surfaced to the user as metres.
//
// Two cheap cues are combined:
//
//   1. Broadband loudness (RMS -> dBFS). Nearer sources are louder, all else
//      equal.
//   2. A direct-to-reverberant ratio (DRR) proxy via onset sharpness. A near,
//      direct sound has a sharp attack and most of its energy concentrated
//      right after onset; a far/reverberant sound is smeared, with relatively
//      more energy in the decay tail. We estimate this from the short-time
//      energy envelope as an early-to-late energy ratio around the onset — a
//      lightweight stand-in for a full impulse-response early/late split.
//
// Loudness alone is easily fooled (a quiet source up close vs. a loud one far
// away), so the DRR proxy is what keeps this honest; confidence drops when the
// two cues disagree or the signal is near the noise floor.

import Foundation
import Accelerate

struct OnsetProximityEstimator: ProximityEstimator {

    // MARK: Tunables

    /// Envelope frame length in samples (~5.3 ms at 48 kHz), non-overlapping.
    let frameLength: Int
    /// dBFS mapped to loudness score 1.0 (near) and 0.0 (far).
    let nearLoudnessDB: Float
    let farLoudnessDB: Float
    /// Early/late energy ratio (dB) mapped to sharpness score 1.0 and 0.0.
    let nearDRRDB: Float
    let farDRRDB: Float

    init(frameLength: Int = 256,
         nearLoudnessDB: Float = -15,
         farLoudnessDB: Float = -55,
         nearDRRDB: Float = 6,
         farDRRDB: Float = -6) {
        self.frameLength = frameLength
        self.nearLoudnessDB = nearLoudnessDB
        self.farLoudnessDB = farLoudnessDB
        self.nearDRRDB = nearDRRDB
        self.farDRRDB = farDRRDB
    }

    // MARK: - ProximityEstimator

    func estimateProximity(_ buffer: AudioBuffer) -> ProximityEstimate {
        let samples = buffer.monoMix()
        guard samples.count >= frameLength else {
            return ProximityEstimate(bucket: .far, confidence: 0)
        }

        // --- Cue 1: broadband loudness ---
        let rms = rootMeanSquare(samples)
        let loudnessDB = amplitudeToDB(rms)
        let loudnessScore = normalize(loudnessDB, high: nearLoudnessDB, low: farLoudnessDB)

        // --- Cue 2: onset-based DRR proxy ---
        let envelope = energyEnvelope(samples)
        let drrDB = directToReverberantDB(envelope, sampleRate: buffer.sampleRate)
        let sharpnessScore = normalize(drrDB, high: nearDRRDB, low: farDRRDB)

        // Weighted blend: loudness leads, sharpness disambiguates.
        let score = 0.6 * loudnessScore + 0.4 * sharpnessScore

        let bucket: ProximityBucket
        switch score {
        case 0.6...:  bucket = .near
        case 0.3..<0.6: bucket = .mid
        default:      bucket = .far
        }

        let confidence = confidence(loudnessDB: loudnessDB,
                                    loudnessScore: loudnessScore,
                                    sharpnessScore: sharpnessScore,
                                    score: score)

        return ProximityEstimate(bucket: bucket, confidence: confidence)
    }

    // MARK: - DRR proxy

    /// Non-overlapping short-time energy envelope (mean-square per frame).
    private func energyEnvelope(_ samples: [Float]) -> [Float] {
        let frameCount = samples.count / frameLength
        guard frameCount > 0 else { return [] }
        var env = [Float](repeating: 0, count: frameCount)
        samples.withUnsafeBufferPointer { buf in
            for f in 0..<frameCount {
                var ms: Float = 0
                vDSP_measqv(buf.baseAddress! + f * frameLength, 1, &ms, vDSP_Length(frameLength))
                env[f] = ms
            }
        }
        return env
    }

    /// Early-to-late energy ratio (dB) measured around the onset (loudest
    /// frame). "Early" ≈ first 12 ms after onset (direct sound), "late" ≈ the
    /// following ~80 ms (reverberant tail).
    private func directToReverberantDB(_ env: [Float], sampleRate: Double) -> Float {
        guard !env.isEmpty else { return farDRRDB }

        // Onset = frame of peak energy.
        var onset = 0
        var peak = env[0]
        for i in 1..<env.count where env[i] > peak { peak = env[i]; onset = i }

        let framesPerSecond = sampleRate / Double(frameLength)
        let earlyFrames = max(1, Int((0.012 * framesPerSecond).rounded()))
        let lateFrames  = max(1, Int((0.080 * framesPerSecond).rounded()))

        let earlyEnd = min(env.count, onset + earlyFrames)
        let lateEnd  = min(env.count, earlyEnd + lateFrames)

        let early = env[onset..<earlyEnd].reduce(0, +)
        let late  = env[earlyEnd..<lateEnd].reduce(0, +)

        // No tail captured (buffer too short after onset) -> treat as ambiguous.
        guard late > 1e-9 else { return (nearDRRDB + farDRRDB) / 2 }
        let ratio = early / late
        return 10 * log10(max(ratio, 1e-9))
    }

    // MARK: - Confidence

    /// High when the signal is well above the noise floor AND the two cues
    /// agree AND the score sits decisively inside a bucket.
    private func confidence(loudnessDB: Float,
                            loudnessScore: Float,
                            sharpnessScore: Float,
                            score: Float) -> Float {
        // Energy gate: ~0 at −60 dBFS, ~1 by −25 dBFS.
        let energyConf = clamp((loudnessDB + 60) / 35)

        // Agreement between the two independent cues.
        let agreement = 1 - abs(loudnessScore - sharpnessScore)

        // Decisiveness: distance from the nearest bucket boundary (0.3 / 0.6).
        let boundaryDist = min(abs(score - 0.3), abs(score - 0.6))
        let decisiveness = clamp(boundaryDist / 0.3)

        return clamp(energyConf * (0.5 * agreement + 0.5 * decisiveness))
    }

    // MARK: - Helpers

    private func rootMeanSquare(_ x: [Float]) -> Float {
        var ms: Float = 0
        vDSP_measqv(x, 1, &ms, vDSP_Length(x.count))
        return ms.squareRoot()
    }

    private func amplitudeToDB(_ amp: Float) -> Float {
        20 * log10(max(amp, 1e-7))
    }

    private func normalize(_ value: Float, high: Float, low: Float) -> Float {
        clamp((value - low) / (high - low))
    }

    private func clamp(_ v: Float) -> Float { min(1, max(0, v)) }
}
