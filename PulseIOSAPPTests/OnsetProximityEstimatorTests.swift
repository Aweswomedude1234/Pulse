// OnsetProximityEstimatorTests.swift
// =============================================================================
// Smoke test for the proximity estimator. See the note in
// GCCPHATDirectionEstimatorTests about wiring a unit-test target.
// =============================================================================

import Testing
import Foundation
@testable import PulseIOSAPP

struct OnsetProximityEstimatorTests {

    private let sampleRate = 48_000.0

    /// Deterministic broadband noise in [-1, 1].
    private func noise(count: Int, seed: UInt64) -> [Float] {
        var state = seed
        var out = [Float](repeating: 0, count: count)
        for i in 0..<count {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            out[i] = Float(state >> 40) / Float(1 << 24) * 2 - 1
        }
        return out
    }

    private func buffer(_ samples: [Float]) -> AudioBuffer {
        AudioBuffer(channels: [samples],
                    sampleRate: sampleRate,
                    frameCount: samples.count,
                    captureTime: Date(),
                    sampleTime: 0)
    }

    /// Loud, sharp onset with fast decay — a "near/direct" signature.
    private func nearSignal(frames N: Int) -> [Float] {
        let src = noise(count: N, seed: 1)
        return src.enumerated().map { i, s in
            let env = expf(-Float(i) / Float(N) * 8)   // fast decay
            return s * env * 0.9                        // loud
        }
    }

    /// Quiet, smeared, sustained signal — a "far/reverberant" signature.
    private func farSignal(frames N: Int) -> [Float] {
        noise(count: N, seed: 2).map { $0 * 0.02 }      // quiet, flat envelope
    }

    @Test("A loud sharp onset reads nearer than a quiet smeared signal")
    func nearVsFar() {
        let est = OnsetProximityEstimator()
        let near = est.estimateProximity(buffer(nearSignal(frames: 8192)))
        let far  = est.estimateProximity(buffer(farSignal(frames: 8192)))

        // Bucket ordering: near ∈ {near, mid}, far ∈ {mid, far}, and near ≥ far.
        #expect(near.bucket == .near || near.bucket == .mid)
        #expect(far.bucket == .far || far.bucket == .mid)
        #expect(order(near.bucket) >= order(far.bucket))
    }

    @Test("Silence yields low confidence")
    func silenceLowConfidence() {
        let est = OnsetProximityEstimator()
        let result = est.estimateProximity(buffer([Float](repeating: 0, count: 8192)))
        #expect(result.confidence < 0.1)
    }

    private func order(_ b: ProximityBucket) -> Int {
        switch b { case .near: return 2; case .mid: return 1; case .far: return 0 }
    }
}
