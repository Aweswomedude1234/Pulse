// BaselineModeView.swift
// =============================================================================
// Feature 1 UI — the always-on, low-cost default. A live transcript panel above
// a scrolling list of identified sounds. No radar here (no direction/proximity
// in Baseline).
// =============================================================================

import SwiftUI

struct BaselineModeView: View {
    @State private var engine = BaselineModeEngine()

    var body: some View {
        VStack(spacing: 0) {
            transcriptPanel
            Divider()
            soundsList
            controls
        }
        .safeAreaInset(edge: .top) { banners }
        .onDisappear { Task { await engine.stop() } }
    }

    // MARK: - Transcript

    private var transcriptPanel: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(engine.transcriptLines.enumerated()), id: \.offset) { _, line in
                        Text(line).foregroundStyle(.primary)
                    }
                    if !engine.partialTranscript.isEmpty {
                        Text(engine.partialTranscript)
                            .foregroundStyle(.secondary)
                            .id("partial")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .frame(height: 160)
            .background(.quaternary.opacity(0.3))
            .onChange(of: engine.partialTranscript) { _, _ in
                withAnimation { proxy.scrollTo("partial", anchor: .bottom) }
            }
            .overlay {
                if engine.transcriptLines.isEmpty && engine.partialTranscript.isEmpty {
                    ContentUnavailableView("No speech yet",
                                           systemImage: "waveform",
                                           description: Text("On-device transcription appears here."))
                }
            }
        }
    }

    // MARK: - Sounds

    private var soundsList: some View {
        List {
            Section("Detected sounds") {
                if engine.detections.isEmpty {
                    Text("Listening…").foregroundStyle(.secondary)
                }
                ForEach(engine.detections) { detection in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(detection.label).font(.body)
                            Text(detection.timestamp.formatted(date: .omitted, time: .standard))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(Int((detection.confidence * 100).rounded()))%")
                            .font(.caption).foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Controls

    private var controls: some View {
        HStack {
            Button(engine.isRunning ? "Stop" : "Start Listening") {
                Task { engine.isRunning ? await engine.stop() : await engine.start() }
            }
            .buttonStyle(.borderedProminent)
            .tint(engine.isRunning ? .red : .green)

            Spacer()

            Button("Clear") { engine.clear() }
                .disabled(engine.detections.isEmpty && engine.transcriptLines.isEmpty)
        }
        .padding()
    }

    // MARK: - Banners

    @ViewBuilder
    private var banners: some View {
        switch engine.state {
        case .permissionDenied:
            banner("Microphone access denied. Enable it in Settings.",
                   icon: "mic.slash.fill", color: .red)
        case .error(let message):
            banner("Couldn't start: \(message)", icon: "exclamationmark.triangle.fill", color: .red)
        default:
            EmptyView()
        }
    }

    private func banner(_ text: String, icon: String, color: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.caption).foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.9))
    }
}

#Preview {
    BaselineModeView()
}
