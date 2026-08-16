// DiagnosticsView.swift
// =============================================================================
// Live pipeline diagnostics, read straight off the SINGLE live audio owner
// (AudioEngine) and its downstream consumers. This view NEVER starts its own
// engine or session — it only observes already-published state, so it cannot
// contend with capture.
//
// Reachable via a long-press on the Settings title, or the DEBUG-only row at the
// bottom of Settings. Physical device only: the Simulator reports mono
// passthrough and no Neural Engine, so the stereo/correlation rows are
// meaningless there.
// =============================================================================

import SwiftUI
import Speech

struct DiagnosticsView: View {

    @EnvironmentObject private var audioEngine: AudioEngine
    @EnvironmentObject private var soundClassifier: SoundClassifier
    @EnvironmentObject private var speech: SpeechRecognitionEngine
    @Environment(\.dismiss) private var dismiss

    // Shared singletons (no new ownership).
    @ObservedObject private var battery = BatteryOptimizationManager.shared

    var body: some View {
        NavigationStack {
            List {
                captureSection
                directionSection
                classifierSection
                transcriptionSection
                powerSection
            }
            .navigationTitle("Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Capture (Subsystem A/B foundation)

    private var captureSection: some View {
        Section {
            if !audioEngine.isRunning {
                Label("Engine not running — activate listening to see live data.",
                      systemImage: "pause.circle")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            }
            row("Input format", audioEngine.inputFormatDescription)
            row("Channel count", "\(audioEngine.inputChannelCount)",
                tint: audioEngine.inputChannelCount >= 2 ? .green : .red)
            correlationRow
            row("RMS L", String(format: "%.4f", audioEngine.leftChannelLevel))
            row("RMS R", String(format: "%.4f", audioEngine.rightChannelLevel))
            row("Loudness", String(format: "%.1f dBFS", audioEngine.currentDecibels))
        } header: {
            Text("Capture")
        } footer: {
            Text(captureVerdict)
        }
    }

    private var correlationRow: some View {
        let c = audioEngine.interChannelCorrelation
        let stereo = audioEngine.inputChannelCount >= 2
        let tint: Color = !stereo ? .red : (c > 0.98 ? .red : (c > 0.9 ? .orange : .green))
        return row("Inter-channel corr", String(format: "%.3f", c), tint: tint)
    }

    private var captureVerdict: String {
        guard audioEngine.isRunning else { return "Waiting for capture to start." }
        if audioEngine.inputChannelCount < 2 {
            return "⚠️ Mono capture — no bearings are possible. Stereo request failed."
        }
        if audioEngine.interChannelCorrelation > 0.98 {
            return "⚠️ Two channels but correlation ≈ 1.0 — duplicated mono (fake stereo). Bearings would be meaningless."
        }
        return "✓ Distinct L/R channels — usable for TDOA direction."
    }

    // MARK: - Direction (pending Subsystem B port)

    private var directionSection: some View {
        Section("Direction · GCC-PHAT") {
            row("Peak lag", "— (pending port)", tint: .secondary)
            row("Peak-to-sidelobe", "— (pending port)", tint: .secondary)
        }
    }

    // MARK: - Classifier

    private var classifierSection: some View {
        Section("Classifier · top 3") {
            if soundClassifier.latestClassifications.isEmpty {
                Text("No classifications yet.")
                    .foregroundStyle(.secondary).font(.footnote)
            } else {
                ForEach(soundClassifier.latestClassifications.prefix(3)) { result in
                    row(result.soundType.displayName,
                        String(format: "%.0f%%", result.confidence * 100))
                }
            }
        }
    }

    // MARK: - Transcription

    private var transcriptionSection: some View {
        Section("Transcription") {
            row("Authorization", speechAuthText, tint: speechAuthTint)
            row("Recognizing", speech.isRecognizing ? "yes" : "no",
                tint: speech.isRecognizing ? .green : .secondary)
            row("Latest partial",
                speech.latestTranscription.isEmpty ? "—" : speech.latestTranscription)
        }
    }

    private var speechAuthText: String {
        switch speech.authorizationStatus {
        case .authorized:    return "authorized"
        case .denied:        return "denied"
        case .restricted:    return "restricted"
        case .notDetermined: return "not determined"
        @unknown default:    return "unknown"
        }
    }

    private var speechAuthTint: Color {
        speech.authorizationStatus == .authorized ? .green : .red
    }

    // MARK: - Power / thermal

    private var powerSection: some View {
        Section("Power · thermal") {
            row("Power profile", battery.currentProfile.description)
            row("Thermal state", battery.thermalDescription, tint: battery.thermalColor)
            row("Low Power Mode", battery.isLowPowerModeEnabled ? "on" : "off",
                tint: battery.isLowPowerModeEnabled ? .orange : .secondary)
            row("Battery", battery.batteryPercentText)
        }
    }

    // MARK: - Row helper

    private func row(_ label: String, _ value: String, tint: Color = .primary) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(tint)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
        }
        .font(.callout)
    }
}
