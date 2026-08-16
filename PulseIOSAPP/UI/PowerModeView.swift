// PowerModeView.swift
// =============================================================================
// Feature 2 UI — the Power Mode screen. A prominent burst toggle over the live
// radar. Tapping "Scan" runs a ~10 s high-fidelity window and populates the map;
// a separate switch keeps it running while foregrounded.
// =============================================================================

import SwiftUI

struct PowerModeView: View {
    @State private var orchestrator = PowerModeOrchestrator()
    @State private var keepOn = false
    @State private var selected: RadarEvent?

    /// Burst length.
    private let burstDuration: TimeInterval = 10

    var body: some View {
        ZStack {
            RadarMapView(events: orchestrator.events) { selected = $0 }
                .ignoresSafeArea()

            VStack {
                statusBanners
                Spacer()
                controls
            }
            .padding()
        }
        .sheet(item: $selected) { RadarEventDetailSheet(event: $0) }
        .onChange(of: keepOn) { _, on in
            Task { on ? await orchestrator.startContinuous() : await orchestrator.stop() }
        }
        .onDisappear { Task { await orchestrator.stop() } }
    }

    // MARK: - Controls

    @ViewBuilder
    private var controls: some View {
        VStack(spacing: 16) {
            burstButton

            Toggle(isOn: $keepOn) {
                Label("Keep listening", systemImage: "infinity")
                    .foregroundStyle(PulseTheme.ink)
            }
            .tint(PulseTheme.accent)
            .padding(.horizontal)
            .disabled(orchestrator.state == .permissionDenied)

            if !orchestrator.events.isEmpty {
                Button("Clear", role: .destructive) { orchestrator.clearEvents() }
                    .font(.footnote)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(PulseTheme.surface)
                .shadow(color: Color.black.opacity(0.06), radius: 16, x: 0, y: 8)
        )
    }

    @ViewBuilder
    private var burstButton: some View {
        let running = orchestrator.isRunning && !keepOn
        Button {
            Task {
                if orchestrator.isRunning {
                    await orchestrator.stop()
                } else {
                    await orchestrator.startBurst(duration: burstDuration)
                }
            }
        } label: {
            HStack {
                Image(systemName: running ? "stop.fill" : "dot.radiowaves.left.and.right")
                Text(running ? "Stop" : "Scan surroundings")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(running ? PulseTheme.danger : PulseTheme.accent, in: Capsule())
            .foregroundStyle(.white)
        }
        .disabled(keepOn)
    }

    // MARK: - Status

    @ViewBuilder
    private var statusBanners: some View {
        VStack(spacing: 8) {
            switch orchestrator.state {
            case .permissionDenied:
                banner("Microphone access denied. Enable it in Settings to use Power Mode.",
                       icon: "mic.slash.fill", color: Color(hex: "#1E4235"))
            case .error(let message):
                banner("Couldn't start: \(message)", icon: "exclamationmark.triangle.fill", color: Color(hex: "#1E4235"))
            case .running where !orchestrator.isStereo:
                banner("Mono input — direction estimation disabled on this device.",
                       icon: "arrow.left.and.right", color: .orange)
            default:
                EmptyView()
            }

            if orchestrator.usingPlaceholderModel {
                banner("Using placeholder classifier — add a model (see MODEL_SETUP.md).",
                       icon: "cpu", color: .yellow)
            }
        }
    }

    private func banner(_ text: String, icon: String, color: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.caption)
            .foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.85), in: RoundedRectangle(cornerRadius: 10))
    }
}

#Preview {
    PowerModeView()
}
