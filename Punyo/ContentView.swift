import SwiftUI

struct ContentView: View {
    @State private var params = PunyoParameters()
    @State private var physics = PunyoPhysics()
    @State private var settings = PunyoRenderSettings()
    @State private var panelExpanded = false
    @State private var haptics = PunyoHapticEngine()

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                TimelineView(.animation) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    let _ = stepPhysics(time: t)
                    PunyoShaderView(
                        physics: physics,
                        params: params,
                        settings: settings
                    ) {
                        background
                    }
                }

                DebugSliderPanel(
                    params: params,
                    settings: settings,
                    physics: physics,
                    isExpanded: $panelExpanded
                )
            }
            .contentShape(Rectangle())
            .gesture(dragGesture)
            .onAppear {
                physics.bounds = geo.size
                physics.setRest(CGPoint(x: geo.size.width / 2,
                                        y: geo.size.height / 2))
            }
            .onChange(of: geo.size) { _, new in
                physics.bounds = new
                physics.setRest(CGPoint(x: new.width / 2, y: new.height / 2))
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
                    // Kick continuous haptics off at a low baseline so the
                    // contact itself has a felt onset before deformation ramps up.
                    haptics.begin(intensity: 0.2, sharpness: 0.3)
                } else {
                    physics.updateTouch(to: value.location, time: now)
                }
            }
            .onEnded { _ in
                physics.endTouch()
                haptics.end()
            }
    }

    private func stepPhysics(time: TimeInterval) {
        physics.step(time: time, params: params)

        // Consumed outside the touch check so a capture that lands on the same
        // frame as the release still fires, and never leaks into the next touch.
        if physics.consumeCapturePop() {
            haptics.capturePop()
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
