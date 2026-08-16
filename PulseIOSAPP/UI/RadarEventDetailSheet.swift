// RadarEventDetailSheet.swift
// =============================================================================
// Detail shown when a radar blip is tapped: full label, confidence, timestamp,
// bearing (with honest uncertainty + front/back note), proximity, and the
// transcript excerpt for speech events.
// =============================================================================

import SwiftUI

struct RadarEventDetailSheet: View {
    let event: RadarEvent

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: event.category.systemImageName)
                            .font(.title2)
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(event.category.tint, in: RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading) {
                            Text(event.label).font(.headline)
                            Text(event.category.displayName)
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        if event.isDanger {
                            Spacer()
                            Label(event.dangerTier.displayName,
                                  systemImage: event.dangerTier.systemImageName)
                                .font(.caption).foregroundStyle(event.dangerTier.accent)
                        }
                    }
                }

                Section("Detection") {
                    row("Confidence", percent(event.confidence))
                    row("Time", event.timestamp.formatted(date: .omitted, time: .standard))
                }

                if let bearing = event.bearing {
                    Section("Direction") {
                        row("Bearing", degrees(bearing.angle))
                        row("Uncertainty", "±\(degreesValue(bearing.uncertainty))°")
                        if bearing.frontBackAmbiguous {
                            Label("Front/back ambiguous — could be the mirrored direction",
                                  systemImage: "arrow.up.arrow.down")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                if let proximity = event.proximity {
                    Section("Proximity") {
                        row("Estimate", proximity.bucket.rawValue.capitalized)
                        row("Confidence", percent(proximity.confidence))
                        Text("Relative estimate only — not a distance measurement.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }

                if let transcript = event.transcript, !transcript.isEmpty {
                    Section("Transcript") {
                        Text(transcript).font(.body)
                    }
                }
            }
            .navigationTitle("Sound Detail")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Helpers

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
    }

    private func percent(_ v: Float) -> String { "\(Int((v * 100).rounded()))%" }

    private func degrees(_ radians: Double) -> String {
        let deg = Int((radians * 180 / .pi).rounded())
        let side = deg == 0 ? "ahead" : (deg > 0 ? "right" : "left")
        return "\(abs(deg))° \(side)"
    }

    private func degreesValue(_ radians: Double) -> Int {
        Int((radians * 180 / .pi).rounded())
    }
}

#Preview {
    RadarEventDetailSheet(event: RadarEvent(
        label: "Smoke detector, smoke alarm",
        category: .alarm,
        confidence: 0.94,
        bearing: BearingEstimate(angle: 1.0, uncertainty: 0.35,
                                 frontBackAmbiguous: true, confidence: 0.9),
        proximity: ProximityEstimate(bucket: .mid, confidence: 0.7),
        transcript: nil))
}
