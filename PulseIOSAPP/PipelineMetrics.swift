// PipelineMetrics.swift
// Lightweight on-device instrumentation for the audio pipeline (change C0).
//
// Captures the numbers we currently have NO baseline for:
//   - per-class detection latency (onset → alert)
//   - false-positive candidates per minute in quiet ambient
//   - tier activation counts (energy gate → VAD → light → heavy + Whisper)
//   - per-experiment event log for A/B comparison
//
// Uses os_signpost so the same events show up on the Instruments timeline next to
// the Core ML / Energy templates. All storage is bounded and in-memory; nothing is
// persisted or transmitted.

import Foundation
import os

@MainActor
final class PipelineMetrics: ObservableObject {

    static let shared = PipelineMetrics()

    private let log = OSLog(subsystem: "com.pulse.app", category: "pipeline")

    // MARK: - Tiered dispatch counters

    enum Tier: String, CaseIterable {
        case energyGate      // buffers that passed the energy floor
        case vad             // windows VAD flagged as speech
        case lightClassifier // SNClassifySound invocations that produced a candidate
        case heavyClassifier // custom EfficientNet invocations
        case whisper         // transcription invocations
    }

    @Published private(set) var tierCounts: [Tier: Int] = [:]
    @Published private(set) var recentDetections: [DetectionSample] = []

    struct DetectionSample: Identifiable {
        let id = UUID()
        let label: String
        let confidence: Float
        let latencyMs: Double?   // onset → alert, when an onset time is known
        let timestamp: Date
        let arm: String          // active experiment arm summary
    }

    // MARK: - API

    func tick(_ tier: Tier) {
        tierCounts[tier, default: 0] += 1
        os_signpost(.event, log: log, name: "tier", "%{public}s", tier.rawValue)
    }

    /// Record a fired detection. `onset` is the time the sound is believed to have
    /// started (e.g. first buffer that crossed the energy floor) so we can measure
    /// end-to-end alert latency against the 500 ms safety budget.
    func recordDetection(label: String,
                         confidence: Float,
                         onset: Date? = nil,
                         arm: String) {
        let latency = onset.map { Date().timeIntervalSince($0) * 1000 }
        let sample = DetectionSample(label: label,
                                     confidence: confidence,
                                     latencyMs: latency,
                                     timestamp: Date(),
                                     arm: arm)
        recentDetections.insert(sample, at: 0)
        if recentDetections.count > 200 {
            recentDetections = Array(recentDetections.prefix(200))
        }
        if let latency {
            os_signpost(.event, log: log, name: "detection",
                        "%{public}s %.0fms conf=%.2f", label, latency, confidence)
        }
    }

    /// Log an arbitrary experiment event for later A/B analysis.
    func recordExperimentEvent(_ name: String, metadata: [String: String] = [:]) {
        let meta = metadata.map { "\($0)=\($1)" }.joined(separator: " ")
        os_signpost(.event, log: log, name: "experiment", "%{public}s %{public}s", name, meta)
    }

    func reset() {
        tierCounts.removeAll()
        recentDetections.removeAll()
    }

    // MARK: - Snapshot (for a debug overlay / test assertions)

    struct Snapshot {
        let tierCounts: [Tier: Int]
        let detectionCount: Int
        let medianLatencyMs: Double?
        let maxLatencyMs: Double?
    }

    func snapshot() -> Snapshot {
        let latencies = recentDetections.compactMap(\.latencyMs).sorted()
        let median = latencies.isEmpty ? nil : latencies[latencies.count / 2]
        return Snapshot(tierCounts: tierCounts,
                        detectionCount: recentDetections.count,
                        medianLatencyMs: median,
                        maxLatencyMs: latencies.last)
    }
}
