// GCCPHATDirectionEstimatorTests.swift
// =============================================================================
// Smoke test for the GCC-PHAT direction estimator using two synthetic buffers
// where one channel is a known integer-sample delay of the other. Broadband
// deterministic noise is used (a pure sine defeats PHAT whitening).
//
// NOTE ON WIRING: the project currently has no unit-test target. Add one in
// Xcode (File ▸ New ▸ Target ▸ Unit Testing Bundle, host = PulseIOSAPP) and add
// this file to it. The test itself is target-agnostic.
// =============================================================================

import Testing
import Foundation
@testable import PulseIOSAPP

struct GCCPHATDirectionEstimatorTests {

    // Fixed geometry so expected angles are deterministic.
    private let sampleRate = 48_000.0
    private let micSpacing = 0.14
    private let speedOfSound = 343.0

    private func estimator() -> GCCPHATDirectionEstimator {
        GCCPHATDirectionEstimator(micSpacing: micSpacing, speedOfSound: speedOfSound)
    }

    /// Deterministic broadband noise in [-1, 1] via a simple LCG (reproducible).
    private func noise(count: Int, seed: UInt64) -> [Float] {
        var state = seed
        var out = [Float](repeating: 0, count: count)
        for i in 0..<count {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let u = Float(state >> 40) / Float(1 << 24)   // [0, 1)
            out[i] = u * 2 - 1
        }
        return out
    }

    /// Builds a stereo buffer where `right` is `left` advanced by `delay`
    /// samples — i.e. the right mic hears the source first (source to the right,
    /// positive bearing by convention).
    private func stereoBuffer(delaySamples D: Int, frames N: Int) -> AudioBuffer {
        // Keep both slice starts non-negative while preserving rightStart -
        // leftStart == D, so a positive D means the right channel leads.
        let source = noise(count: N + abs(D) + 1, seed: 0xC0FFEE)
        let leftStart  = max(0, -D)
        let rightStart = max(0, D)
        let left  = Array(source[leftStart..<(leftStart + N)])
        let right = Array(source[rightStart..<(rightStart + N)])
        return AudioBuffer(channels: [left, right],
                           sampleRate: sampleRate,
                           frameCount: N,
                           captureTime: Date(),
                           sampleTime: 0)
    }

    private func expectedAngle(delaySamples D: Int) -> Double {
        let tau = Double(D) / sampleRate
        let x = min(1, max(-1, tau * speedOfSound / micSpacing))
        return asin(x)
    }

    @Test("Recovers a right-leading delay as a positive bearing")
    func rightSource() throws {
        let D = 10
        let buffer = stereoBuffer(delaySamples: D, frames: 4096)
        let estimate = try #require(estimator().estimateBearing(buffer))

        #expect(estimate.angle > 0)                       // source to the right
        #expect(abs(estimate.angle - expectedAngle(delaySamples: D)) < 0.05)
        #expect(estimate.frontBackAmbiguous)              // two-mic array
        #expect(estimate.confidence > 0.3)                // clean, distinct peak
        #expect(estimate.uncertainty > 0)                 // never a crisp point
    }

    @Test("Recovers a left-leading delay as a negative bearing")
    func leftSource() throws {
        let D = -8
        let buffer = stereoBuffer(delaySamples: D, frames: 4096)
        let estimate = try #require(estimator().estimateBearing(buffer))

        #expect(estimate.angle < 0)                       // source to the left
        #expect(abs(estimate.angle - expectedAngle(delaySamples: D)) < 0.05)
    }

    @Test("Zero delay reads as roughly straight ahead")
    func centeredSource() throws {
        let buffer = stereoBuffer(delaySamples: 0, frames: 4096)
        let estimate = try #require(estimator().estimateBearing(buffer))
        #expect(abs(estimate.angle) < 0.05)
    }

    @Test("Mono input yields no bearing rather than a fake one")
    func monoReturnsNil() {
        let mono = noise(count: 4096, seed: 1)
        let buffer = AudioBuffer(channels: [mono],
                                 sampleRate: sampleRate,
                                 frameCount: mono.count,
                                 captureTime: Date(),
                                 sampleTime: 0)
        #expect(estimator().estimateBearing(buffer) == nil)
    }

    @Test("Silence yields no bearing")
    func silenceReturnsNil() {
        let silent = [Float](repeating: 0, count: 4096)
        let buffer = AudioBuffer(channels: [silent, silent],
                                 sampleRate: sampleRate,
                                 frameCount: silent.count,
                                 captureTime: Date(),
                                 sampleTime: 0)
        #expect(estimator().estimateBearing(buffer) == nil)
    }
}
