// PipelineProtocols.swift
// =============================================================================
// PRIVACY BANNER — NO NETWORKING IN THE AUDIO PATH.
// Nothing in this file or anything conforming to these protocols may make a
// network call. Audio, transcripts, and events never leave the device.
// =============================================================================
//
// Protocol-oriented seams for the Pulse audio pipeline. Everything here is
// swappable and testable without a live microphone: feed a fake `AudioSource`
// and assert on the outputs.
//
//   AudioSource          -> AsyncStream<AudioBuffer>
//   SoundClassifier      -> [ClassificationResult]
//   DirectionEstimator   -> BearingEstimate (angle, uncertainty, ambiguity)
//   ProximityEstimator   -> ProximityEstimate (bucket + confidence)
//   EventStore           -> SoundEvent persistence
//   PowerGovernor        -> current tier + thermal/battery reactions
//
// Swift 6: all value types crossing an actor/async boundary are `Sendable`.

import Foundation

// MARK: - AudioBuffer

/// A single window of captured PCM audio, decoupled from AVFoundation so the
/// rest of the pipeline can be exercised with synthetic buffers in tests.
///
/// Samples are stored **de-interleaved**, one `[Float]` per channel. Mono
/// capture yields a single channel; stereo yields `[left, right]`. Downstream
/// direction estimation requires `channels.count == 2`.
struct AudioBuffer: Sendable {

    /// De-interleaved sample data. `channels[0]` is left/mono, `channels[1]`
    /// (when present) is right. Every channel has `frameCount` samples.
    let channels: [[Float]]

    /// Samples per second (e.g. 48_000).
    let sampleRate: Double

    /// Number of frames (samples) per channel.
    let frameCount: Int

    /// Wall-clock capture time of the first frame, for event timestamping.
    let captureTime: Date

    /// Monotonic audio sample time of the first frame (seconds), for aligning
    /// consecutive buffers without wall-clock jitter.
    let sampleTime: Double

    var channelCount: Int { channels.count }
    var isStereo: Bool { channels.count >= 2 }

    /// Convenience mono mixdown (channel average) for energy/mel work that does
    /// not care about inter-channel phase.
    func monoMix() -> [Float] {
        guard let first = channels.first else { return [] }
        guard channels.count > 1 else { return first }
        var out = first
        let scale = 1.0 / Float(channels.count)
        for c in 1..<channels.count {
            let ch = channels[c]
            for i in 0..<min(out.count, ch.count) { out[i] += ch[i] }
        }
        for i in 0..<out.count { out[i] *= scale }
        return out
    }
}

// MARK: - AudioSource

/// A producer of `AudioBuffer`s. The live implementation wraps AVAudioEngine;
/// tests inject a scripted stream.
protocol AudioSource: Sendable {

    /// Begin capture and return the stream of buffers. Throws if the audio
    /// session or engine cannot be configured.
    func start() async throws -> AsyncStream<AudioBuffer>

    /// Stop capture and finish the stream.
    func stop() async

    /// Whether the source is currently delivering true stereo. When `false`,
    /// direction estimation must be disabled rather than faked.
    var isStereo: Bool { get async }
}

// MARK: - Classification

/// One label hypothesis for a buffer.
struct ClassificationResult: Sendable, Identifiable, Hashable {
    let id: UUID
    /// Raw model label (e.g. a YAMNet class such as "Smoke detector, smoke alarm").
    let label: String
    /// Coarse app-facing category the label maps to.
    let category: SoundCategory
    /// Model confidence in [0, 1].
    let confidence: Float
    /// Whether this label represents human speech (gates transcription).
    let isSpeech: Bool

    init(id: UUID = UUID(),
         label: String,
         category: SoundCategory,
         confidence: Float,
         isSpeech: Bool) {
        self.id = id
        self.label = label
        self.category = category
        self.confidence = confidence
        self.isSpeech = isSpeech
    }
}

/// Model-agnostic classifier seam. Default target is a YAMNet-class 521-label
/// Core ML model; AST/BEATs can be dropped in behind the same interface.
protocol SoundClassifier: Sendable {
    /// Return ranked label hypotheses for a buffer (best first, may be empty).
    func classify(_ buffer: AudioBuffer) async -> [ClassificationResult]
}

// MARK: - Direction

/// Coarse bearing from classical TDOA (GCC-PHAT). Honest about its limits: with
/// ~10–14 cm mic spacing this is a left/right bearing with front/back ambiguity,
/// not a precise angle — hence the explicit uncertainty and ambiguity flag.
struct BearingEstimate: Sendable, Hashable {
    /// Estimated bearing in radians. 0 = ahead, +π/2 = right, −π/2 = left.
    let angle: Double
    /// Half-width of the uncertainty cone in radians. The UI renders a wedge of
    /// this width rather than a point.
    let uncertainty: Double
    /// True when the geometry cannot disambiguate front from back; the UI draws
    /// a mirrored ghost wedge.
    let frontBackAmbiguous: Bool
    /// Confidence in [0, 1] derived from the cross-correlation peak sharpness.
    let confidence: Float
}

/// Estimates bearing from a stereo buffer. Returns `nil` for mono buffers or
/// when no reliable peak is found.
protocol DirectionEstimator: Sendable {
    func estimateBearing(_ buffer: AudioBuffer) -> BearingEstimate?
}

// MARK: - Proximity

/// Relative proximity bucket. There is no true distance measurement here; this
/// is a coarse relative estimate and must never be presented as meters.
enum ProximityBucket: String, Sendable, Codable, CaseIterable {
    case near
    case mid
    case far
}

struct ProximityEstimate: Sendable, Hashable {
    let bucket: ProximityBucket
    /// Confidence in [0, 1].
    let confidence: Float
}

/// Estimates a relative proximity bucket from broadband RMS combined with a
/// direct-to-reverberant / onset-sharpness proxy.
protocol ProximityEstimator: Sendable {
    func estimateProximity(_ buffer: AudioBuffer) -> ProximityEstimate
}

// MARK: - Persistence

/// Local-only persistence for events. Implementations use SwiftData; no sync.
protocol EventStore: Sendable {
    func save(_ event: SoundEvent) async
    func recent(within window: TimeInterval) async -> [SoundEvent]
    func deleteAll() async
}

// MARK: - Power governance

/// Operating tier for the pipeline, ordered by cost.
enum PowerTier: Int, Sendable, Comparable, CaseIterable {
    /// Cheap always-available path: SoundAnalysis + on-device speech only.
    case baseline = 0
    /// Full high-fidelity burst: direction + proximity + heavy classifier.
    case power = 1
    /// Settings-gated background monitoring with duty cycling.
    case alwaysOn = 2

    static func < (lhs: PowerTier, rhs: PowerTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Owns the thermal/battery governor and the currently active tier. Reacts to
/// `ProcessInfo.thermalState` and low-power mode by stepping down. This is part
/// of the pipeline, not bolted-on polish.
protocol PowerGovernor: Sendable {
    var currentTier: PowerTier { get async }
    /// Request a tier; the governor may grant a lower one under thermal/battery
    /// pressure and returns what was actually granted.
    func requestTier(_ tier: PowerTier) async -> PowerTier
    /// Stream of effective-tier changes (including forced step-downs).
    func tierChanges() -> AsyncStream<PowerTier>
}
