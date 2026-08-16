// AlwaysOnSettingsView.swift
// =============================================================================
// Feature 3 UI — the settings-gated, multi-step confirmation flow for Always-On
// Power Mode (beta). OFF by default; enabling requires walking an explicit
// warning flow; turning it off is a single tap (trivially reversible).
// =============================================================================

import SwiftUI

struct AlwaysOnSettingsView: View {
    @AppStorage("alwaysOnEnabled") private var enabled = false
    @State private var engine = AlwaysOnEngine()
    @State private var showingFlow = false

    var body: some View {
        List {
            Section {
                if enabled {
                    runningRow
                    Button("Turn Off Always-On", role: .destructive) {
                        enabled = false
                        Task { await engine.stop() }
                    }
                } else {
                    Button {
                        showingFlow = true
                    } label: {
                        Label("Enable Always-On (Beta)", systemImage: "bolt.badge.clock")
                    }
                }
            } header: {
                Text("Always-On Power Mode")
            } footer: {
                Text("Beta. Monitors continuously with the screen off. Off by default.")
            }

            Section("What to expect") {
                bullet("Significant battery drain", "battery.25")
                bullet("The device may get warm", "thermometer.medium")
                bullet("A persistent orange mic indicator", "mic.fill")
                bullet("May stop if the system needs resources", "exclamationmark.triangle")
            }
        }
        .navigationTitle("Always-On")
        .sheet(isPresented: $showingFlow) {
            AlwaysOnConfirmationFlow {
                enabled = true
                Task { await engine.start() }
            }
        }
        .task(id: enabled) {
            // Reconcile engine with the stored flag (e.g. after relaunch).
            if enabled && !engine.isRunning { await engine.start() }
        }
    }

    private var runningRow: some View {
        HStack {
            Label("Monitoring", systemImage: "dot.radiowaves.left.and.right")
            Spacer()
            Text(statusText)
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var statusText: String {
        switch engine.state {
        case .running:          return "Active · \(engine.stage.rawValue)"
        case .permissionDenied: return "Mic denied"
        case .error(let m):     return m
        case .idle:             return "Starting…"
        }
    }

    private func bullet(_ text: String, _ icon: String) -> some View {
        Label(text, systemImage: icon)
    }
}

// MARK: - Confirmation flow

private struct AlwaysOnConfirmationFlow: View {
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    private enum Step: Int { case intro, warnings, confirm }
    @State private var step: Step = .intro
    @State private var ackBattery = false
    @State private var ackBeta = false

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .intro:    intro
                case .warnings: warnings
                case .confirm:  confirm
                }
            }
            .padding()
            .navigationTitle("Enable Always-On")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .interactiveDismissDisabled()
    }

    private var intro: some View {
        VStack(spacing: 20) {
            Image(systemName: "bolt.badge.clock")
                .font(.system(size: 52)).foregroundStyle(.yellow)
            Text("Always-On keeps listening with the screen off so you don't miss important sounds — alarms, knocking, someone calling out.")
                .multilineTextAlignment(.center)
            Text("This is a beta feature.")
                .font(.footnote).foregroundStyle(.secondary)
            Spacer()
            Button("Continue") { step = .warnings }
                .buttonStyle(.borderedProminent)
        }
    }

    private var warnings: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("It will drain your battery noticeably and may warm the device.",
                  systemImage: "battery.25").foregroundStyle(.orange)
            Label("The orange microphone indicator stays on the whole time.",
                  systemImage: "mic.fill")
            Label("If iOS terminates the app, monitoring won't restart on its own — you'll get a notification.",
                  systemImage: "exclamationmark.triangle")
            Divider()
            Toggle("I understand the battery and heat impact.", isOn: $ackBattery)
            Toggle("I understand this is beta and may stop unexpectedly.", isOn: $ackBeta)
            Spacer()
            Button("Continue") { step = .confirm }
                .buttonStyle(.borderedProminent)
                .disabled(!(ackBattery && ackBeta))
                .frame(maxWidth: .infinity)
        }
    }

    private var confirm: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.shield")
                .font(.system(size: 52)).foregroundStyle(.green)
            Text("You can turn Always-On off at any time in Settings.")
                .multilineTextAlignment(.center)
            Spacer()
            Button("Enable Always-On") {
                onConfirm()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        }
    }
}

#Preview {
    NavigationStack { AlwaysOnSettingsView() }
}
