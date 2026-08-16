// StereoAudioCapture.swift
// =============================================================================
// PRIVACY BANNER — NO NETWORKING IN THE AUDIO PATH.
// Captured audio lives only in-memory and is emitted to in-process consumers.
// Nothing here writes to disk or opens a socket.
// =============================================================================
//
// Live `AudioSource` for Power Mode. Configures the session for measurement-grade
// stereo capture and taps the AVAudioEngine input.
//
// Key requirements this satisfies:
//   • Category `.record`, mode `.measurement` — defeats AGC / processing that
//     would wreck the L/R phase relationship GCC-PHAT depends on.
//   • Requests the built-in mic's stereo polar pattern via the port's data
//     sources + `setPreferredPolarPattern(.stereo)`.
//   • `setPreferredInputOrientation` from the current device orientation so the
//     stereo image is aligned to how the phone is held.
//   • Graceful degradation: if stereo can't be obtained, capture mono and report
//     `isStereo == false` so direction estimation is disabled rather than faked.

import Foundation
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif

actor StereoAudioCapture: AudioSource {

    // MARK: Configuration

    /// Preferred capture rate. Hardware may hand back its own; we resample-free
    /// and just record whatever the input node actually provides.
    private let preferredSampleRate: Double = 48_000
    /// Tap buffer size in frames (~21 ms at 48 kHz). Small enough for responsive
    /// direction/energy windows, large enough to avoid tap overhead.
    private let tapBufferSize: AVAudioFrameCount = 1024

    // MARK: State

    private let engine = AVAudioEngine()
    private var continuation: AsyncStream<AudioBuffer>.Continuation?
    private var running = false
    private var stereoActive = false

    var isStereo: Bool { stereoActive }

    // MARK: - AudioSource

    func start() async throws -> AsyncStream<AudioBuffer> {
        // If already running, tear down first so callers get a clean stream.
        if running { await stop() }

        try configureSession()

        let (stream, continuation) = AsyncStream<AudioBuffer>.makeStream(
            bufferingPolicy: .bufferingNewest(8)
        )
        self.continuation = continuation

        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        stereoActive = format.channelCount >= 2

        // The tap block runs on a real-time audio thread. Capture only Sendable
        // values and hop into the actor to publish.
        input.installTap(onBus: 0,
                         bufferSize: tapBufferSize,
                         format: format) { [weak self] pcm, when in
            guard let self else { return }
            guard let event = Self.makeBuffer(from: pcm, when: when) else { return }
            Task { await self.yield(event) }
        }

        engine.prepare()
        try engine.start()
        running = true
        return stream
    }

    func stop() async {
        guard running else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        continuation?.finish()
        continuation = nil
        running = false
        stereoActive = false

        #if os(iOS)
        // Relinquish the session so other audio can resume. Ignore failures —
        // the session may already be inactive.
        try? AVAudioSession.sharedInstance().setActive(false,
                                                       options: .notifyOthersOnDeactivation)
        #endif
    }

    // MARK: - Publishing

    private func yield(_ buffer: AudioBuffer) {
        continuation?.yield(buffer)
    }

    // MARK: - Session configuration

    private func configureSession() throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()

        // `.measurement` mode is the important part: it disables the input AGC
        // and signal conditioning that would otherwise destroy inter-channel
        // phase and defeat TDOA direction estimation.
        try session.setCategory(.record, mode: .measurement, options: [])
        try session.setPreferredSampleRate(preferredSampleRate)
        try session.setActive(true, options: [])

        configureStereoInput(on: session)
        #endif
    }

    #if os(iOS)
    /// Best-effort request for the built-in mic's stereo polar pattern and an
    /// input orientation matching how the device is held. Any step may be
    /// unsupported on a given device; we degrade to mono without erroring.
    private func configureStereoInput(on session: AVAudioSession) {
        guard let input = session.availableInputs?.first(where: {
            $0.portType == .builtInMic
        }) else { return }

        do {
            try session.setPreferredInput(input)
        } catch {
            return
        }

        // Find a data source that advertises the stereo polar pattern.
        let stereoSource = input.dataSources?.first { source in
            source.supportedPolarPatterns?.contains(.stereo) ?? false
        }

        guard let source = stereoSource else {
            // No stereo-capable data source — stay mono.
            return
        }

        do {
            try source.setPreferredPolarPattern(.stereo)
            try input.setPreferredDataSource(source)
            try session.setPreferredInputOrientation(currentInputOrientation())
        } catch {
            // Leave whatever partial config succeeded; `isStereo` is derived
            // from the actual input format at tap time, so this stays honest.
        }
    }

    /// Maps the current device orientation to a stereo input orientation so the
    /// L/R image lines up with the physical mics.
    private func currentInputOrientation() -> AVAudioSession.StereoOrientation {
        #if canImport(UIKit)
        switch UIDevice.current.orientation {
        case .portrait:            return .portrait
        case .portraitUpsideDown:  return .portraitUpsideDown
        case .landscapeLeft:       return .landscapeLeft
        case .landscapeRight:      return .landscapeRight
        default:                   return .portrait
        }
        #else
        return .portrait
        #endif
    }
    #endif

    // MARK: - Conversion

    /// Extracts de-interleaved float channels from an AVAudioPCMBuffer. Returns
    /// `nil` for unsupported formats or empty buffers. `nonisolated static` so
    /// it can run on the real-time tap thread without touching actor state.
    private nonisolated static func makeBuffer(from pcm: AVAudioPCMBuffer,
                                               when: AVAudioTime) -> AudioBuffer? {
        let frames = Int(pcm.frameLength)
        guard frames > 0 else { return nil }
        guard let floatData = pcm.floatChannelData else { return nil }

        let channelCount = Int(pcm.format.channelCount)
        var channels: [[Float]] = []
        channels.reserveCapacity(channelCount)
        for c in 0..<channelCount {
            let ptr = floatData[c]
            channels.append(Array(UnsafeBufferPointer(start: ptr, count: frames)))
        }

        let sampleRate = pcm.format.sampleRate
        let sampleTime = when.isSampleTimeValid
            ? Double(when.sampleTime) / sampleRate
            : 0

        return AudioBuffer(channels: channels,
                           sampleRate: sampleRate,
                           frameCount: frames,
                           captureTime: Date(),
                           sampleTime: sampleTime)
    }
}
