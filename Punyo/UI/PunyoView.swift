import SwiftUI

// Phase 0 placeholder rendering: colored circle that squishes along the
// deformation vector. Will be replaced by SDF/SSS/refraction shader
// techniques in later PRs.
struct PunyoView: View {
    let physics: PunyoPhysics

    var body: some View {
        let d = physics.deformation
        let magnitude = hypot(d.dx, d.dy)
        let squish = min(magnitude / physics.radius, 0.6)
        let angle = atan2(d.dy, d.dx)

        Circle()
            .fill(
                RadialGradient(
                    colors: [Color(red: 0.95, green: 0.55, blue: 0.85),
                             Color(red: 0.55, green: 0.25, blue: 0.75)],
                    center: .init(x: 0.35, y: 0.3),
                    startRadius: 4, endRadius: physics.radius
                )
            )
            .frame(width: physics.radius * 2, height: physics.radius * 2)
            .scaleEffect(x: 1.0 - squish * 0.55, y: 1.0 + squish * 0.35, anchor: .center)
            .rotationEffect(.radians(angle))
            .position(physics.center)
            .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
            .allowsHitTesting(false)
    }
}
