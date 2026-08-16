// GCCPHATDirectionEstimator.swift
// =============================================================================
// PRIVACY BANNER — NO NETWORKING IN THE AUDIO PATH.
// Pure on-device signal processing. No I/O of any kind.
// =============================================================================
//
// Classical TDOA direction estimation via GCC-PHAT (Generalized Cross
// Correlation with Phase Transform), implemented on vDSP FFTs. NOT machine
// learning.
//
// Honesty about what this yields: with ~10–14 cm of mic spacing on a phone we
// recover a COARSE left/right bearing with inherent FRONT/BACK AMBIGUITY — a
// two-mic broadside array physically cannot tell front from back. We therefore
// always report `frontBackAmbiguous == true`, and we return an uncertainty cone
// (not a crisp angle) that widens as the correlation peak gets less sharp.
//
// Pipeline:
//   1. De-interleaved L/R -> zero-padded to a power of two >= 2·N.
//   2. Forward DFT of each channel (complex, imaginary part zero).
//   3. Cross-power spectrum  X = L · conj(R), PHAT-whitened  X /= |X|.
//   4. Inverse DFT -> cross-correlation r(τ).
//   5. Peak within the physically-plausible lag window, parabolic-interpolated
//      to sub-sample resolution.
//   6. τ -> bearing via  angle = asin(clamp(τ·c / d, −1, 1)).
//
// Sign convention: +τ means the RIGHT channel led the LEFT (sound reached the
// right mic first) -> source to the right -> positive angle. 0 = ahead.

import Foundation
import Accelerate

struct GCCPHATDirectionEstimator: DirectionEstimator {

    // MARK: Physical configuration

    /// Distance between the two effective microphones, metres. Phones land in
    /// the 10–14 cm range; 0.14 m is a conservative default.
    let micSpacing: Double
    /// Speed of sound, metres/second (dry air ~20°C).
    let speedOfSound: Double
    /// Maximum number of input frames used per channel (bounds FFT cost).
    let maxAnalysisFrames: Int

    init(micSpacing: Double = 0.14,
         speedOfSound: Double = 343.0,
         maxAnalysisFrames: Int = 8192) {
        self.micSpacing = micSpacing
        self.speedOfSound = speedOfSound
        self.maxAnalysisFrames = maxAnalysisFrames
    }

    // MARK: - DirectionEstimator

    func estimateBearing(_ buffer: AudioBuffer) -> BearingEstimate? {
        // Mono cannot yield a bearing — never fake one.
        guard buffer.channelCount >= 2 else { return nil }

        let usedLen = min(buffer.frameCount, maxAnalysisFrames)
        guard usedLen >= 64 else { return nil }

        var left  = Array(buffer.channels[0].prefix(usedLen))
        var right = Array(buffer.channels[1].prefix(usedLen))
        if left.count != right.count { return nil }

        // Reject silence: PHAT whitening on noise-floor-only audio yields a
        // meaningless peak.
        let energy = rms(left) + rms(right)
        guard energy > 1e-5 else { return nil }

        // FFT length: power of two >= 2·N so the circular correlation does not
        // wrap real lags into each other.
        let n = nextPowerOfTwo(usedLen * 2)
        left.append(contentsOf: repeatElement(0, count: n - left.count))
        right.append(contentsOf: repeatElement(0, count: n - right.count))

        guard let correlation = gccPhat(left, right, n: n) else { return nil }

        // Physically plausible lag window from the mic geometry.
        let maxLag = max(1, Int((micSpacing / speedOfSound * buffer.sampleRate).rounded(.up)))

        guard let peak = peakLag(in: correlation, n: n, maxLag: maxLag) else { return nil }

        // Sub-sample lag -> time delay -> bearing.
        let tau = peak.lag / buffer.sampleRate
        var x = tau * speedOfSound / micSpacing
        x = min(1, max(-1, x))
        let angle = asin(x)

        let confidence = peak.confidence
        let uncertainty = uncertaintyCone(atX: x,
                                          sampleRate: buffer.sampleRate,
                                          confidence: confidence)

        return BearingEstimate(angle: angle,
                               uncertainty: uncertainty,
                               frontBackAmbiguous: true, // two-mic array — always
                               confidence: confidence)
    }

    // MARK: - GCC-PHAT core

    /// Returns the PHAT-weighted cross-correlation (length `n`, lag index 0 at
    /// element 0, wrapping so index > n/2 is a negative lag).
    private func gccPhat(_ a: [Float], _ b: [Float], n: Int) -> [Float]? {
        guard
            let forward = try? vDSP.DiscreteFourierTransform(
                count: n, direction: .forward,
                transformType: .complexComplex, ofType: Float.self),
            let inverse = try? vDSP.DiscreteFourierTransform(
                count: n, direction: .inverse,
                transformType: .complexComplex, ofType: Float.self)
        else { return nil }

        let zeros = [Float](repeating: 0, count: n)
        let fa = forward.transform(real: a, imaginary: zeros)
        let fb = forward.transform(real: b, imaginary: zeros)

        // Cross-power spectrum X = A · conj(B), then PHAT whitening X /= |X|.
        var xr = [Float](repeating: 0, count: n)
        var xi = [Float](repeating: 0, count: n)
        for k in 0..<n {
            let ar = fa.real[k], ai = fa.imaginary[k]
            let br = fb.real[k], bi = fb.imaginary[k]
            var cr = ar * br + ai * bi   // real(A·conj(B))
            var ci = ai * br - ar * bi   // imag(A·conj(B))
            let mag = (cr * cr + ci * ci).squareRoot()
            if mag > 1e-9 {
                cr /= mag
                ci /= mag
            }
            xr[k] = cr
            xi[k] = ci
        }

        let corr = inverse.transform(real: xr, imaginary: xi)
        // Real part is the cross-correlation; scale is irrelevant (we only use
        // relative peak location + sharpness).
        return corr.real
    }

    // MARK: - Peak detection

    private struct Peak { let lag: Double; let confidence: Float }

    /// Finds the correlation peak within ±maxLag, with parabolic sub-sample
    /// interpolation, and derives a confidence from peak sharpness.
    private func peakLag(in corr: [Float], n: Int, maxLag: Int) -> Peak? {
        // Search both positive lags (indices 1...maxLag) and negative lags
        // (indices n-maxLag ... n-1), plus zero lag.
        var bestIdx = 0
        var bestVal = corr[0]
        for offset in 0...maxLag {
            let pos = offset
            if corr[pos] > bestVal { bestVal = corr[pos]; bestIdx = pos }
            if offset > 0 {
                let neg = n - offset
                if corr[neg] > bestVal { bestVal = corr[neg]; bestIdx = neg }
            }
        }
        guard bestVal > 0 else { return nil }

        // Integer lag, mapped to signed range.
        let signedInt = bestIdx <= n / 2 ? bestIdx : bestIdx - n

        // Parabolic interpolation using neighbours (wrapping).
        let ym1 = corr[(bestIdx - 1 + n) % n]
        let y0  = corr[bestIdx]
        let yp1 = corr[(bestIdx + 1) % n]
        let denom = ym1 - 2 * y0 + yp1
        let delta = denom != 0 ? 0.5 * Double(ym1 - yp1) / Double(denom) : 0
        let lag = Double(signedInt) + max(-0.5, min(0.5, delta))

        // Confidence from peak-to-sidelobe: compare the peak against the RMS of
        // the correlation across the plausible window.
        let confidence = peakConfidence(corr, n: n, maxLag: maxLag, peak: y0)
        return Peak(lag: lag, confidence: confidence)
    }

    private func peakConfidence(_ corr: [Float], n: Int, maxLag: Int, peak: Float) -> Float {
        var sumSq: Float = 0
        var count = 0
        for offset in 0...maxLag {
            let p = corr[offset]; sumSq += p * p; count += 1
            if offset > 0 { let q = corr[n - offset]; sumSq += q * q; count += 1 }
        }
        let rmsVal = (sumSq / Float(max(1, count))).squareRoot()
        guard rmsVal > 1e-9 else { return 0 }
        // Peak/RMS is ~1 for noise, grows with a distinct peak. Map [1, 4] -> [0, 1].
        let ratio = peak / rmsVal
        return min(1, max(0, (ratio - 1) / 3))
    }

    // MARK: - Uncertainty

    /// Angular half-width of the reported cone. Combines the angular cost of a
    /// one-sample lag quantisation at this bearing (asin is steep near ±90°)
    /// with a confidence-driven widening.
    private func uncertaintyCone(atX x: Double, sampleRate: Double, confidence: Float) -> Double {
        let dtau = 1.0 / sampleRate
        let dxdtau = speedOfSound / micSpacing
        // d(angle)/d(tau) = (c/d) / sqrt(1 - x²)
        let denom = max(1e-3, (1 - x * x).squareRoot())
        let anglePerSample = abs(dxdtau * dtau) / denom
        let quantization = 0.5 * anglePerSample

        let maxCone = 30.0 * .pi / 180.0   // widest cone at zero confidence
        let widening = Double(1 - confidence) * maxCone

        // Clamp to a sane [~2°, 60°] range.
        let raw = quantization + widening
        return min(60.0 * .pi / 180.0, max(2.0 * .pi / 180.0, raw))
    }

    // MARK: - Helpers

    private func rms(_ x: [Float]) -> Float {
        guard !x.isEmpty else { return 0 }
        var mean: Float = 0
        vDSP_measqv(x, 1, &mean, vDSP_Length(x.count))
        return mean.squareRoot()
    }

    private func nextPowerOfTwo(_ value: Int) -> Int {
        var n = 1
        while n < value { n <<= 1 }
        return n
    }
}
