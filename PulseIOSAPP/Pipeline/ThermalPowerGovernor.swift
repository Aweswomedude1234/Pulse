// ThermalPowerGovernor.swift
// =============================================================================
// PRIVACY BANNER — NO NETWORKING IN THE AUDIO PATH.
// =============================================================================
//
// The thermal/battery governor. This is part of the pipeline, not bolted-on
// polish: it observes ProcessInfo.thermalState and Low Power Mode and forces the
// pipeline down when the device is under stress.
//
//   • .nominal / .fair, not low-power  -> full policy (requested tier, all stages)
//   • .serious  OR  Low Power Mode     -> step down: drop transcription, widen
//                                         the duty cycle, cap tier at .power
//   • .critical                        -> fall back to Baseline Mode entirely
//
// It publishes both a coarse `PowerTier` (the protocol contract) and a richer
// `PowerPolicy` the Always-On engine reads for its stage/duty decisions.

import Foundation
import Observation

/// Concrete operating policy derived from the requested tier + device stress.
struct PowerPolicy: Sendable, Equatable {
    var tier: PowerTier
    /// Whether the (expensive) transcription stage may run.
    var transcriptionEnabled: Bool
    /// Multiplier on the Always-On duty-cycle cool-down (≥1 widens it).
    var dutyCycleMultiplier: Double
    /// Human-readable reason for any step-down (for surfacing to the user).
    var reason: String?

    static let full = PowerPolicy(tier: .alwaysOn,
                                  transcriptionEnabled: true,
                                  dutyCycleMultiplier: 1,
                                  reason: nil)
}

@MainActor
@Observable
final class ThermalPowerGovernor: PowerGovernor {

    private(set) var policy: PowerPolicy = .full
    private var requestedTier: PowerTier = .baseline

    private var tierContinuations: [AsyncStream<PowerTier>.Continuation] = []
    private var policyContinuations: [AsyncStream<PowerPolicy>.Continuation] = []

    init() {
        let center = NotificationCenter.default
        center.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification,
                           object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.recompute() }
        }
        center.addObserver(forName: .NSProcessInfoPowerStateDidChange,
                           object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.recompute() }
        }
        recompute()
    }

    // MARK: - PowerGovernor

    var currentTier: PowerTier { get async { policy.tier } }

    func requestTier(_ tier: PowerTier) async -> PowerTier {
        requestedTier = tier
        recompute()
        return policy.tier
    }

    func tierChanges() -> AsyncStream<PowerTier> {
        AsyncStream { continuation in
            continuation.yield(policy.tier)
            tierContinuations.append(continuation)
        }
    }

    /// Richer stream for the Always-On engine.
    func policyChanges() -> AsyncStream<PowerPolicy> {
        AsyncStream { continuation in
            continuation.yield(policy)
            policyContinuations.append(continuation)
        }
    }

    // MARK: - Governor logic

    private func recompute() {
        let thermal = ProcessInfo.processInfo.thermalState
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

        let newPolicy: PowerPolicy
        switch thermal {
        case .critical:
            newPolicy = PowerPolicy(tier: .baseline,
                                    transcriptionEnabled: false,
                                    dutyCycleMultiplier: 4,
                                    reason: "Device is too hot — dropped to Baseline Mode.")
        case .serious:
            newPolicy = PowerPolicy(tier: min(requestedTier, .power),
                                    transcriptionEnabled: false,
                                    dutyCycleMultiplier: 2,
                                    reason: "Device is warm — transcription off, checking less often.")
        default:
            if lowPower {
                newPolicy = PowerPolicy(tier: min(requestedTier, .power),
                                        transcriptionEnabled: false,
                                        dutyCycleMultiplier: 2,
                                        reason: "Low Power Mode — transcription off, checking less often.")
            } else {
                newPolicy = PowerPolicy(tier: requestedTier,
                                        transcriptionEnabled: true,
                                        dutyCycleMultiplier: 1,
                                        reason: nil)
            }
        }

        guard newPolicy != policy else { return }
        let tierChanged = newPolicy.tier != policy.tier
        policy = newPolicy

        for c in policyContinuations { c.yield(newPolicy) }
        if tierChanged { for c in tierContinuations { c.yield(newPolicy.tier) } }
    }
}
