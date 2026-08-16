// WatchViews.swift
// The watch UI: a three-page vertical TabView —
//   1. Home          — the current noises (latest 2–3) + source badge + haptics.
//   2. Notifications — alert/danger events that warrant attention.
//   3. Phone         — companion connection status + live captions from the phone.

import SwiftUI

// MARK: - Root

struct WatchRootView: View {
    @EnvironmentObject private var session: WatchSessionManager

    var body: some View {
        TabView {
            HomeView()
            NotificationsView()
            PhoneView()
        }
        .tabViewStyle(.verticalPage)
    }
}

// MARK: - Home (current noises)

struct HomeView: View {
    @EnvironmentObject private var session: WatchSessionManager

    private var current: [WatchDetection] {
        Array(session.recentDetections.prefix(3))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                SourceBadge(source: session.activeSource, micDenied: session.micDenied)

                if current.isEmpty {
                    ListeningPlaceholder(source: session.activeSource)
                } else {
                    ForEach(current) { detection in
                        DetectionCard(detection: detection)
                    }
                }
            }
            .padding(.horizontal, 2)
        }
        .navigationTitle("Pulse")
    }
}

/// A prominent card for a single current noise.
private struct DetectionCard: View {
    let detection: WatchDetection

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(detection.type.accentColor.opacity(0.22))
                Image(systemName: detection.type.systemImageName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(detection.type.accentColor)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 2) {
                Text(detection.type.displayName)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    if let direction = detection.direction {
                        Image(systemName: "location.north.fill")
                            .rotationEffect(direction.arrowRotation)
                        Text(direction.humanReadable)
                    } else {
                        Text(detection.timestamp, style: .time)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(detection.type.accentColor.opacity(detection.type.isDangerous ? 0.16 : 0.10))
        )
    }
}

/// Shows what the app is currently doing when there are no noises yet.
private struct ListeningPlaceholder: View {
    let source: WatchSessionManager.ActiveSource

    private var text: String {
        switch source {
        case .phone: return "Listening via iPhone…"
        case .watch: return "Listening on Apple Watch…"
        case .idle:  return "Tap to start listening"
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: source == .idle ? "ear" : "waveform")
                .font(.system(size: 28))
                .foregroundStyle(source == .idle ? Color.secondary : Color(hex: "#2E69F2"))
                .symbolEffect(.variableColor.iterative, isActive: source != .idle)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 26)
    }
}

/// Small badge indicating where detections are coming from.
private struct SourceBadge: View {
    let source: WatchSessionManager.ActiveSource
    let micDenied: Bool

    private var label: String {
        if micDenied && source == .watch { return "Mic access needed" }
        switch source {
        case .phone: return "iPhone"
        case .watch: return "Watch"
        case .idle:  return "Idle"
        }
    }

    private var icon: String {
        if micDenied && source == .watch { return "mic.slash.fill" }
        switch source {
        case .phone: return "iphone"
        case .watch: return "applewatch"
        case .idle:  return "pause.circle"
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(label)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Notifications (alerts)

struct NotificationsView: View {
    @EnvironmentObject private var session: WatchSessionManager

    private var alerts: [WatchDetection] {
        session.recentDetections.filter { $0.type.isDangerous || $0.type.isAlert }
    }

    var body: some View {
        List {
            if alerts.isEmpty {
                Text("No alerts")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(alerts) { detection in
                    AlertRow(detection: detection)
                }
            }
        }
        .navigationTitle("Alerts")
    }
}

private struct AlertRow: View {
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
                    if detection.type.isDangerous {
                        Text("DANGER").foregroundStyle(detection.type.accentColor)
                    }
                    Text(detection.timestamp, style: .time)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Phone (connection + captions)

struct PhoneView: View {
    @EnvironmentObject private var session: WatchSessionManager

    var body: some View {
        List {
            Section {
                HStack {
                    Label("iPhone", systemImage: "iphone")
                    Spacer()
                    Text(session.isReachable ? "Connected" : "Not reachable")
                        .foregroundStyle(session.isReachable ? Color(hex: "#27C281") : .secondary)
                }
                .font(.footnote)
            }

            Section("Live Captions") {
                if session.transcripts.isEmpty {
                    Text(session.isReachable ? "No speech captured" : "Captions require iPhone")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(session.transcripts) { line in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.text).font(.footnote)
                            Text(line.timestamp, style: .time)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 1)
                    }
                }
            }
        }
        .navigationTitle("Phone")
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Home") {
    HomeView().environmentObject(WatchSessionManager.previewPopulated())
}

#Preview("Alerts") {
    NotificationsView().environmentObject(WatchSessionManager.previewPopulated())
}

#Preview("Phone") {
    PhoneView().environmentObject(WatchSessionManager.previewPopulated())
}
#endif
