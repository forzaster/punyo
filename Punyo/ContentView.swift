import SwiftUI

struct ContentView: View {
    @State private var params = PunyoParameters()
    @State private var physics = PunyoPhysics()
    @State private var settings = PunyoRenderSettings()
    @State private var panelExpanded = false
    @State private var haptics = PunyoHapticEngine()
    @State private var speaker = PunyoSpeaker()
    @State private var recorder = PunyoGestureRecorder()
    @State private var modelSource = FoundationModelSpeechSource()
    // Kept across catches so the descriptor can spot repeated手癖.
    @State private var lastFeatures: PunyoGestureFeatures?

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                TimelineView(.animation) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    // Defer the physics tick out of this body evaluation: mutating
                    // observable state that PunyoShaderView's inner TimelineView
                    // reads back triggers a same-transaction re-eval loop that
                    // pegs the main thread and starves touch delivery entirely.
                    // Task { @MainActor } instead of DispatchQueue so the async
                    // model call inside speaker.speak can be launched from a
                    // main-actor context without extra hops.
                    let _: Task<Void, Never> = Task { @MainActor in step(time: t) }
                    ZStack {
                        PunyoShaderView(
                            physics: physics,
                            params: params,
                            settings: settings
                        ) {
                            background
                        }
                        PunyoEyesView(physics: physics)
                        PunyoSpeechView(speaker: speaker,
                                        anchor: speechAnchor(in: geo.size))
                    }
                }

                // Dedicated touch layer sitting above the shader and below the
                // debug panel. Attaching the drag gesture to a Color.clear with
                // its own contentShape keeps hit-testing predictable: the
                // shader/background can't swallow the touch, and the panel's
                // buttons stay on top because they're rendered after this.
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(dragGesture)

                DebugSliderPanel(
                    params: params,
                    settings: settings,
                    physics: physics,
                    speaker: speaker,
                    modelSource: modelSource,
                    isExpanded: $panelExpanded
                )
            }
            .onAppear {
                physics.bounds = geo.size
                physics.setRest(CGPoint(x: geo.size.width / 2,
                                        y: geo.size.height / 2))
                params.apply(settings.material.physics)
                // On-device model becomes the primary source; the speaker
                // falls back to templates automatically when it declines or
                // is unavailable.
                speaker.source = modelSource
                speaker.persona = modelSource.persona
            }
            .onChange(of: geo.size) { _, new in
                physics.bounds = new
                physics.setRest(CGPoint(x: new.width / 2, y: new.height / 2))
            }
            .onChange(of: settings.material.id) { _, _ in
                params.apply(settings.material.physics)
            }
        }
        .ignoresSafeArea()
    }

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.06, green: 0.07, blue: 0.12),
                         Color(red: 0.14, green: 0.06, blue: 0.18)],
                startPoint: .top, endPoint: .bottom
            )
            // Subtle grid so screen-space refraction is visible when the
            // puni is a translucent lens over the background.
            Canvas { ctx, size in
                let spacing: CGFloat = 42
                let lineColor = Color.white.opacity(0.05)
                var x: CGFloat = 0
                while x <= size.width {
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                    ctx.stroke(path, with: .color(lineColor), lineWidth: 1)
                    x += spacing
                }
                var y: CGFloat = 0
                while y <= size.height {
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    ctx.stroke(path, with: .color(lineColor), lineWidth: 1)
                    y += spacing
                }
            }
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let now = Date().timeIntervalSinceReferenceDate
                if !physics.isFingerDown {
                    physics.beginTouch(at: value.location, time: now)
                    recorder.begin(at: value.location, time: now)
                    // Kick continuous haptics off at a low baseline so the
                    // contact itself has a felt onset before deformation ramps up.
                    haptics.begin(intensity: 0.2, sharpness: 0.3)
                } else {
                    physics.updateTouch(to: value.location, time: now)
                    recorder.record(at: value.location, time: now)
                }
            }
            .onEnded { _ in
                let now = Date().timeIntervalSinceReferenceDate
                physics.endTouch(time: now)
                // A touch that ended without a catch: drop the samples on
                // the floor. Consistent with the privacy rule — no raw
                // trajectory outlives the gesture that produced it.
                recorder.cancel()
                haptics.end()
            }
    }

    // Where the line sits: above the puni, kept clear of the screen edges so a
    // catch in a corner is still readable.
    private func speechAnchor(in size: CGSize) -> CGPoint {
        let margin: CGFloat = 90
        return CGPoint(
            x: min(max(physics.center.x, margin), max(margin, size.width - margin)),
            y: max(60, physics.center.y - physics.radiusMean - 40)
        )
    }

    @MainActor
    private func step(time: TimeInterval) {
        physics.step(time: time, params: params)
        speaker.step(time: time)

        // Consumed outside the touch check so a capture that lands on the same
        // frame as the release still fires, and never leaks into the next touch.
        if let capture = physics.consumeCapture() {
            haptics.capturePop()
            let features = recorder.snapshot(
                endTime: time,
                grabMissCount: physics.perTouchGrabMisses,
                deformationPeak: physics.perTouchDeformationPeak,
                radiusMean: physics.radiusMean
            )
            let descriptor = PunyoDescriptorFactory.make(
                from: features, recentHabit: lastFeatures
            )
            lastFeatures = features
            speaker.speak(for: capture, descriptor: descriptor, at: time)
        }

        guard physics.isFingerDown else { return }
        let level = physics.deformationLevel
        var intensity = Float(0.18 + 0.82 * level)
        var sharpness = Float(0.20 + 0.55 * level)
        if physics.isCaptured {
            // Held: a dull rumble under the squeeze. It's struggling, and the
            // struggle fades as it wears out.
            intensity = max(intensity, Float(0.25 + 0.45 * physics.stamina))
            sharpness = min(sharpness, 0.25)
        }
        haptics.update(intensity: intensity, sharpness: sharpness)
    }
}

#Preview {
    ContentView()
}
