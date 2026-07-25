import Foundation
import CoreGraphics
import Observation

@Observable
final class PunyoPhysics {
    var center: CGPoint = .zero
    var restCenter: CGPoint = .zero
    var velocity: CGVector = .zero

    // Displacement of mass. The surface BULGES in this direction and DENTS
    // on the opposite side. When a finger presses, mass is pushed away from
    // the finger, so this vector points from the finger toward the far side.
    // The shader interprets it identically: bulge where deformation points.
    var deformation: CGVector = .zero
    var deformationVelocity: CGVector = .zero

    var isFingerDown: Bool = false
    var fingerPosition: CGPoint = .zero
    private var lastFingerPosition: CGPoint = .zero
    private var lastFingerTime: TimeInterval = 0
    var fingerVelocity: CGVector = .zero

    private var lastStepTime: TimeInterval?

    let radius: CGFloat = 90

    // Normalized 0..1 measure of how much the puni is currently deformed.
    // Used to drive continuous haptics intensity.
    var deformationLevel: Double {
        let mag = hypot(deformation.dx, deformation.dy)
        let scale = radius * 0.6
        return min(1.0, mag / scale)
    }

    func setRest(_ point: CGPoint) {
        restCenter = point
        if center == .zero {
            center = point
        }
    }

    func beginTouch(at point: CGPoint, time: TimeInterval) {
        isFingerDown = true
        fingerPosition = point
        lastFingerPosition = point
        lastFingerTime = time
        fingerVelocity = .zero
    }

    func updateTouch(to point: CGPoint, time: TimeInterval) {
        let dt = max(0.0001, time - lastFingerTime)
        fingerVelocity = CGVector(
            dx: (point.x - lastFingerPosition.x) / dt,
            dy: (point.y - lastFingerPosition.y) / dt
        )
        lastFingerPosition = fingerPosition
        lastFingerTime = time
        fingerPosition = point
    }

    func endTouch() {
        isFingerDown = false
        fingerVelocity = .zero
    }

    // Current visible deformation magnitude in points (for haptics, UI, etc).
    var deformationMagnitude: CGFloat {
        hypot(deformation.dx, deformation.dy)
    }

    func step(time: TimeInterval, params: PunyoParameters) {
        defer { lastStepTime = time }
        guard let last = lastStepTime else { return }
        let dt = min(1.0 / 30.0, max(0.0, time - last))
        if dt == 0 { return }

        let elasticity = params.elasticity
        let damping = params.damping
        let viscosity = params.viscosity
        let overshoot = params.overshoot

        // --- Body translation: rest spring + contact-gated finger follow ---
        // The body always has a soft spring toward its rest position. Finger
        // follow only starts once the touch is inside the silhouette, and
        // scales with contact depth so a shallow touch nudges while a deep
        // press grips. This prevents an arbitrary touch elsewhere on screen
        // from pulling the puni across the scene.
        let toRest = CGVector(dx: restCenter.x - center.x,
                              dy: restCenter.y - center.y)
        var followForce = CGVector.zero
        if isFingerDown {
            let toFinger = CGVector(dx: fingerPosition.x - center.x,
                                    dy: fingerPosition.y - center.y)
            let distance = hypot(toFinger.dx, toFinger.dy)
            let contactDepth = max(0.0, radius - distance) / radius
            if contactDepth > 0.001 {
                // Higher viscosity makes the body feel heavier while being
                // dragged. A full press retains the strong follow of the
                // direct-target model, but a light touch stays gentle.
                let followScale = 1.0 - viscosity * 0.75
                let followK = elasticity * 0.55 * followScale * contactDepth
                followForce = CGVector(dx: followK * toFinger.dx,
                                       dy: followK * toFinger.dy)
            }
        }

        // The return spring is intentionally softer than the in-contact
        // follow force. Residual velocity after release produces the selected
        // amount of overshoot before the body settles at rest.
        let restK = elasticity * 0.15
        let bodyC = damping * (1.0 - 0.7 * overshoot)
        let ax = restK * toRest.dx + followForce.dx - bodyC * velocity.dx
        let ay = restK * toRest.dy + followForce.dy - bodyC * velocity.dy
        velocity.dx += ax * dt
        velocity.dy += ay * dt
        center.x += velocity.dx * dt
        center.y += velocity.dy * dt

        // --- Deformation: mass pushed away from finger --------------------
        // Direction from finger to (past) center. Bulge appears on the far
        // side, indent on the finger side.
        var targetDeform = CGVector.zero
        if isFingerDown {
            let fromFinger = CGVector(dx: center.x - fingerPosition.x,
                                      dy: center.y - fingerPosition.y)
            let dist = max(0.0001, hypot(fromFinger.dx, fromFinger.dy))
            let overlap = max(0.0, radius - dist)
            if overlap > 0 {
                let dirBulgeX = fromFinger.dx / dist
                let dirBulgeY = fromFinger.dy / dist
                let strength = min(overlap / radius, 1.0)
                targetDeform = CGVector(
                    dx: dirBulgeX * strength * radius * 0.55,
                    dy: dirBulgeY * strength * radius * 0.55
                )
            }
        }

        // Viscosity slows how eagerly deformation chases its target. Higher
        // viscosity => more gooey lag; lower => snappy jelly.
        let deformK = elasticity * 1.6
        let deformC = damping * (1.4 - 0.9 * overshoot)
        let approach = 1.0 - Double(viscosity) * 0.75
        let effectiveTargetX = deformation.dx + (targetDeform.dx - deformation.dx) * approach
        let effectiveTargetY = deformation.dy + (targetDeform.dy - deformation.dy) * approach
        let dax = deformK * (effectiveTargetX - deformation.dx) - deformC * deformationVelocity.dx
        let day = deformK * (effectiveTargetY - deformation.dy) - deformC * deformationVelocity.dy
        deformationVelocity.dx += dax * dt
        deformationVelocity.dy += day * dt
        deformation.dx += deformationVelocity.dx * dt
        deformation.dy += deformationVelocity.dy * dt
    }
}
