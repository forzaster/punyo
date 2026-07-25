import SwiftUI

struct ContentView: View {
    @State private var params = PunyoParameters()
    @State private var physics = PunyoPhysics()
    @State private var panelExpanded = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                background

                TimelineView(.animation) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    let _ = stepPhysics(time: t)
                    PunyoView(physics: physics)
                }

                DebugSliderPanel(params: params, isExpanded: $panelExpanded)
            }
            .contentShape(Rectangle())
            .gesture(dragGesture)
            .onAppear {
                physics.setRest(CGPoint(x: geo.size.width / 2,
                                        y: geo.size.height / 2))
            }
            .onChange(of: geo.size) { _, new in
                physics.setRest(CGPoint(x: new.width / 2, y: new.height / 2))
            }
        }
        .ignoresSafeArea()
    }

    private var background: some View {
        LinearGradient(
            colors: [Color(red: 0.05, green: 0.05, blue: 0.09),
                     Color(red: 0.10, green: 0.05, blue: 0.15)],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let now = Date().timeIntervalSinceReferenceDate
                if !physics.isFingerDown {
                    physics.beginTouch(at: value.location, time: now)
                } else {
                    physics.updateTouch(to: value.location, time: now)
                }
            }
            .onEnded { _ in
                physics.endTouch()
            }
    }

    private func stepPhysics(time: TimeInterval) {
        physics.step(time: time, params: params)
    }
}

#Preview {
    ContentView()
}
