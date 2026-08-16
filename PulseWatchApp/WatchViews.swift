// WatchViews.swift
// The watch UI: a three-page TabView —
//   1. Now      — the most recent detection, glanceable, with direction.
//   2. Recent   — a scrollable list of the last detections.
//   3. Captions — live speech transcription streamed from the phone.

import SwiftUI

// MARK: - Root

struct WatchRootView: View {
    @EnvironmentObject private var session: WatchSessionManager

    var body: some View {
        TabView {
            NowView()
            RecentListView()
            CaptionsView()
        }
        .tabViewStyle(.verticalPage)
    }
}

// MARK: - Now (glanceable latest detection)

struct NowView: View {
    @EnvironmentObject private var session: WatchSessionManager

    var body: some View {
        ScrollView {
            if let detection = session.latestDetection {
                VStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(detection.type.accentColor.opacity(0.22))
                        Image(systemName: detection.type.systemImageName)
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(detection.type.accentColor)
                    }
                    .frame(width: 88, height: 88)

                    Text(detection.type.displayName)
                        .font(.headline)
                        .multilineTextAlignment(.center)

                    if let direction = detection.direction {
                        Label {
                            Text(direction.humanReadable)
                        } icon: {
                            Image(systemName: "location.north.fill")
                                .rotationEffect(direction.arrowRotation)
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }

                    Text("\(Int(detection.confidence * 100))% • \(detection.timestamp, style: .time)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    if detection.type.isDangerous {
                        Text("DANGER")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(detection.type.accentColor.opacity(0.25)))
                            .foregroundStyle(detection.type.accentColor)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            } else {
                WaitingView(reachable: session.isReachable)
            }
        }
        .navigationTitle("Pulse")
    }
}

// MARK: - Recent list

struct RecentListView: View {
    @EnvironmentObject private var session: WatchSessionManager

    var body: some View {
        List {
            if session.recentDetections.isEmpty {
                Text("No sounds yet")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(session.recentDetections) { detection in
                    DetectionRow(detection: detection)
                }
            }
        }
        .navigationTitle("Recent")
    }
}

private struct DetectionRow: View {
    let detection: WatchDetection

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: detection.type.systemImageName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(detection.type.accentColor)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(detection.type.displayName)
                    .font(.footnote.weight(.medium))
                HStack(spacing: 4) {
                    Text(detection.timestamp, style: .time)
                    if let direction = detection.direction {
                        Text("• \(direction.humanReadable)")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Captions

struct CaptionsView: View {
    @EnvironmentObject private var session: WatchSessionManager

    var body: some View {
        List {
            if session.transcripts.isEmpty {
                Text("No speech captured")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(session.transcripts) { line in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(line.text)
                            .font(.footnote)
                        Text(line.timestamp, style: .time)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 1)
                }
            }
        }
        .navigationTitle("Captions")
    }
}

// MARK: - Waiting state

private struct WaitingView: View {
    let reachable: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: reachable ? "waveform" : "iphone.slash")
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
            Text(reachable ? "Listening…" : "Open Pulse on iPhone")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
    }
}
