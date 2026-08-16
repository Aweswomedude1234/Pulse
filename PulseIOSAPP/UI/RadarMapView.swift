// RadarMapView.swift
// =============================================================================
// The signature radar/sonar map. A SwiftUI `Canvas` draws the sonar backdrop,
// the concentric near/mid/far arcs, the rotating sweep, and each event's
// uncertainty WEDGE (angular width = bearing uncertainty; front/back-ambiguous
// events get a mirrored ghost wedge). Tappable blips are overlaid as positioned
// views so hit-testing and SF Symbols stay simple.
//
// Driven purely by an injected `[RadarEvent]` — no pipeline dependency — so it
// renders from fakes today and from the real pipeline later without changes.
// =============================================================================

import SwiftUI

struct RadarMapView: View {

    /// Events to plot. Only events with a bearing appear on the radar; the rest
    /// belong to the scrolling feed.
    let events: [RadarEvent]

    /// Seconds over which a normal event fades to nothing. Danger-tier events
    /// ignore this and stay pinned.
    var decayWindow: TimeInterval = 30

    /// Callback when a blip is tapped (host presents the detail sheet).
    var onSelect: (RadarEvent) -> Void = { _ in }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let maxRadius = side / 2 * 0.9

            // Throttle Canvas redraws to ~12 Hz — plenty for the sweep + decay,
            // and far cheaper than driving it at the display refresh rate.
            TimelineView(.periodic(from: .now, by: 1.0 / 12.0)) { timeline in
                let now = timeline.date
                let placed = placedEvents(now: now, center: center, maxRadius: maxRadius)

                ZStack {
                    Canvas { ctx, _ in
                        drawBackdrop(ctx, center: center, maxRadius: maxRadius)
                        drawSweep(ctx, center: center, maxRadius: maxRadius, now: now)
                        drawWedges(ctx, placed: placed, center: center, maxRadius: maxRadius)
                    }

                    // Center device icon, oriented "ahead" = up.
                    Image(systemName: "iphone.gen3")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(PulseTheme.ink.opacity(0.85))
                        .position(center)

                    // Tappable blips.
                    ForEach(placed, id: \.event.id) { item in
                        RadarBlip(event: item.event, opacity: item.opacity)
                            .position(item.point)
                            .onTapGesture { onSelect(item.event) }
                    }
                }
            }
        }
        .background(
            ZStack {
                PulseTheme.background
                RadialGradient(colors: [PulseTheme.mint.opacity(0.18), .clear],
                               center: .center, startRadius: 8, endRadius: 320)
            }
        )
    }

    // MARK: - Layout

    private struct Placed {
        let event: RadarEvent
        let point: CGPoint
        let opacity: Double
        let ringFraction: CGFloat
    }

    private func placedEvents(now: Date, center: CGPoint, maxRadius: CGFloat) -> [Placed] {
        events.compactMap { event -> Placed? in
            guard let bearing = event.bearing?.angle else { return nil }
            let o = opacity(for: event, now: now)
            guard o > 0.02 else { return nil }
            let frac = RadarGeometry.ringFraction(for: event.proximity?.bucket)
            let p = RadarGeometry.point(angle: bearing, radius: maxRadius * frac, center: center)
            return Placed(event: event, point: p, opacity: o, ringFraction: frac)
        }
        // Danger on top.
        .sorted { !$0.event.isDanger && $1.event.isDanger }
    }

    /// Confidence-driven opacity that decays with age; danger events don't fade.
    private func opacity(for event: RadarEvent, now: Date) -> Double {
        let base = max(0.3, min(1.0, Double(event.confidence)))
        if event.isDanger { return max(base, 0.9) }
        let age = now.timeIntervalSince(event.timestamp)
        guard age >= 0 else { return base }
        return max(0, base * (1 - age / decayWindow))
    }

    // MARK: - Canvas drawing

    private func drawBackdrop(_ ctx: GraphicsContext, center: CGPoint, maxRadius: CGFloat) {
        // Concentric near/mid/far arcs.
        for bucket in [ProximityBucket.near, .mid, .far] {
            let r = maxRadius * RadarGeometry.ringFraction(for: bucket)
            let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
            ctx.stroke(Path(ellipseIn: rect),
                       with: .color(PulseTheme.accent.opacity(0.30)),
                       lineWidth: 1)
            ctx.draw(Text(ringLabel(bucket))
                        .font(.caption2)
                        .foregroundStyle(PulseTheme.inkSoft.opacity(0.7)),
                     at: CGPoint(x: center.x, y: center.y - r + 8))
        }
        // Cross axes.
        var axes = Path()
        axes.move(to: CGPoint(x: center.x - maxRadius, y: center.y))
        axes.addLine(to: CGPoint(x: center.x + maxRadius, y: center.y))
        axes.move(to: CGPoint(x: center.x, y: center.y - maxRadius))
        axes.addLine(to: CGPoint(x: center.x, y: center.y + maxRadius))
        ctx.stroke(axes, with: .color(PulseTheme.accent.opacity(0.15)), lineWidth: 1)
    }

    private func drawSweep(_ ctx: GraphicsContext, center: CGPoint, maxRadius: CGFloat, now: Date) {
        let period = 4.0
        let t = now.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
        let angle = t * 2 * .pi
        let tip = RadarGeometry.point(angle: angle, radius: maxRadius, center: center)
        var line = Path()
        line.move(to: center)
        line.addLine(to: tip)
        ctx.stroke(line, with: .color(PulseTheme.accent.opacity(0.45)), lineWidth: 2)
    }

    private func drawWedges(_ ctx: GraphicsContext, placed: [Placed],
                            center: CGPoint, maxRadius: CGFloat) {
        for item in placed {
            guard let bearing = item.event.bearing else { continue }
            let ringR = maxRadius * item.ringFraction
            let inner = max(0, ringR - 22)
            let outer = ringR + 22
            let tint = item.event.category.tint

            let wedge = RadarGeometry.wedgePath(center: center,
                                                innerRadius: inner,
                                                outerRadius: outer,
                                                bearing: bearing.angle,
                                                halfWidth: bearing.uncertainty)
            ctx.fill(wedge, with: .color(tint.opacity(item.opacity * 0.28)))
            ctx.stroke(wedge, with: .color(tint.opacity(item.opacity * 0.5)), lineWidth: 1)

            // Mirrored ghost wedge for front/back ambiguity.
            if bearing.frontBackAmbiguous {
                let ghost = RadarGeometry.wedgePath(
                    center: center, innerRadius: inner, outerRadius: outer,
                    bearing: RadarGeometry.frontBackMirror(of: bearing.angle),
                    halfWidth: bearing.uncertainty)
                ctx.fill(ghost, with: .color(tint.opacity(item.opacity * 0.12)))
            }
        }
    }

    private func ringLabel(_ bucket: ProximityBucket) -> String {
        switch bucket {
        case .near: return "NEAR"
        case .mid:  return "MID"
        case .far:  return "FAR"
        }
    }
}

// MARK: - Blip

private struct RadarBlip: View {
    let event: RadarEvent
    let opacity: Double

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .fill(event.category.tint.opacity(0.9))
                    .frame(width: 30, height: 30)
                if event.isDanger {
                    Circle()
                        .stroke(event.dangerTier.accent, lineWidth: 2.5)
                        .frame(width: 34, height: 34)
                }
                Image(systemName: event.category.systemImageName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            }
            Text(event.label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(PulseTheme.ink)
                .lineLimit(1)
                .fixedSize()
        }
        .opacity(opacity)
        .shadow(color: event.isDanger ? event.dangerTier.accent.opacity(0.8) : .clear, radius: 6)
    }
}

// MARK: - Demo (drives the map from injected fakes)

/// Standalone demo used during development (build order step 5): plots fake
/// events and lets you emit more, with live decay and the rotating sweep.
struct RadarMapDemoView: View {
    @State private var events: [RadarEvent] = RadarMapDemoView.seed()
    @State private var selected: RadarEvent?

    var body: some View {
        RadarMapView(events: events) { selected = $0 }
            .ignoresSafeArea()
            .overlay(alignment: .bottom) {
                Button {
                    events.append(Self.randomEvent())
                } label: {
                    Label("Emit event", systemImage: "dot.radiowaves.left.and.right")
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .padding(.bottom, 24)
            }
            .sheet(item: $selected) { RadarEventDetailSheet(event: $0) }
    }

    private static func seed() -> [RadarEvent] {
        [
            makeEvent(label: "Speech", category: .speech, bearing: -0.5, unc: 0.25,
                      bucket: .near, confidence: 0.8, transcript: "hey, are you there?"),
            makeEvent(label: "Smoke detector, smoke alarm", category: .alarm, bearing: 1.1,
                      unc: 0.35, bucket: .mid, confidence: 0.95, ambiguous: true),
            makeEvent(label: "Water, running", category: .water, bearing: 2.4, unc: 0.5,
                      bucket: .far, confidence: 0.6, ambiguous: true),
        ]
    }

    private static func randomEvent() -> RadarEvent {
        let cats: [SoundCategory] = [.speech, .alarm, .impact, .alert, .water, .animal, .vehicle]
        let cat = cats.randomElement()!
        return makeEvent(label: cat.displayName,
                         category: cat,
                         bearing: Double.random(in: -(.pi)...(.pi)),
                         unc: Double.random(in: 0.15...0.5),
                         bucket: [.near, .mid, .far].randomElement()!,
                         confidence: Float.random(in: 0.5...1),
                         ambiguous: Bool.random())
    }

    private static func makeEvent(label: String, category: SoundCategory,
                                  bearing: Double, unc: Double, bucket: ProximityBucket,
                                  confidence: Float, ambiguous: Bool = false,
                                  transcript: String? = nil) -> RadarEvent {
        RadarEvent(
            label: label, category: category, confidence: confidence,
            bearing: BearingEstimate(angle: bearing, uncertainty: unc,
                                     frontBackAmbiguous: ambiguous, confidence: confidence),
            proximity: ProximityEstimate(bucket: bucket, confidence: confidence),
            transcript: transcript)
    }
}

#Preview {
    RadarMapDemoView()
}
