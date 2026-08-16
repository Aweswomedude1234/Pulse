// FakeSoundClassifierTests.swift
// =============================================================================
// Smoke test for the deterministic placeholder classifier. See the note in
// GCCPHATDirectionEstimatorTests about wiring a unit-test target.
// =============================================================================

import Testing
import Foundation
@testable import PulseIOSAPP

struct FakeSoundClassifierTests {

    private let sampleRate = 48_000.0

    private func buffer(_ samples: [Float]) -> AudioBuffer {
        AudioBuffer(channels: [samples],
                    sampleRate: sampleRate,
                    frameCount: samples.count,
                    captureTime: Date(),
                    sampleTime: 0)
    }

    /// A tone at `freq` Hz — its zero-crossing rate drives the fake's label.
    private func tone(freq: Double, frames N: Int, amp: Float = 0.5) -> [Float] {
        (0..<N).map { amp * Float(sin(2 * .pi * freq * Double($0) / sampleRate)) }
    }

    @Test("Deterministic: identical input yields identical output")
    func deterministic() async {
        let c = FakeSoundClassifier()
        let b = buffer(tone(freq: 500, frames: 4096))
        let r1 = await c.classify(b)
        let r2 = await c.classify(b)
        #expect(r1 == r2)
        #expect(!r1.isEmpty)
    }

    @Test("Silence produces no detections")
    func silence() async {
        let c = FakeSoundClassifier()
        let r = await c.classify(buffer([Float](repeating: 0, count: 4096)))
        #expect(r.isEmpty)
    }

    @Test("A speech-band tone maps to the speech category")
    func speechBand() async {
        let c = FakeSoundClassifier()
        // ~700 Hz tone -> ~1400 zero-crossings/sec -> "Speech" bucket.
        let r = await c.classify(buffer(tone(freq: 700, frames: 8192)))
        #expect(r.first?.category == .speech)
        #expect(r.first?.isSpeech == true)
    }
}
