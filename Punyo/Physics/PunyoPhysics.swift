import Foundation
import CoreGraphics
import Observation

@Observable
final class PunyoPhysics {
    var center: CGPoint = .zero
    var restCenter: CGPoint = .zero
    var velocity: CGVector = .zero

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

    func step(time: TimeInterval, params: PunyoParameters) {
        defer { lastStepTime = time }
        guard let last = lastStepTime else { return }
        let dt = min(1.0 / 30.0, max(0.0, time - last))
        if dt == 0 { return }

        let elasticity = params.elasticity
        let damping = params.damping
        let viscosity = params.viscosity
        let overshoot = params.overshoot

        // --- Body translation: spring-damper toward a target ---
        // While pressed, the target is the finger position (body gets dragged
        // along with the touch). On release, the target snaps back to restCenter
        // and the residual velocity produces a visible overshoot before settling.
        let bodyTarget: CGPoint = isFingerDown ? fingerPosition : restCenter
        let toTarget = CGVector(dx: bodyTarget.x - center.x,
                                dy: bodyTarget.y - center.y)
        // Follow-mode uses a stronger spring so the ball actually keeps up with
        // the finger; viscosity slows the follow (heavier feel). Settle-mode uses
        // a softer spring so the return wobbles.
        let followScale = 1.0 - Double(viscosity) * 0.75
        let bodyK = isFingerDown
            ? elasticity * 0.55 * followScale
            : elasticity * 0.15
        // Damping ratio: higher `damping` param increases damping; overshoot lowers it.
        let bodyC = damping * (1.0 - 0.7 * overshoot)
        let ax = bodyK * toTarget.dx - bodyC * velocity.dx
        let ay = bodyK * toTarget.dy - bodyC * velocity.dy
        velocity.dx += ax * dt
        velocity.dy += ay * dt
        center.x += velocity.dx * dt
        center.y += velocity.dy * dt

        // --- Deformation: driven by finger push ---
        // Target deformation vector: from finger toward center, magnitude grows as
        // finger overlaps body. Viscosity controls how "sticky/slow" the deform target
        // is pursued.
        var targetDeform = CGVector.zero
        if isFingerDown {
            let toCenter = CGVector(dx: center.x - fingerPosition.x, dy: center.y - fingerPosition.y)
            let dist = max(0.0001, hypot(toCenter.dx, toCenter.dy))
            let overlap = max(0.0, radius - dist)
            // Normalize direction from finger to center: this is the direction the body
            // is being pushed toward. Deformation vector points OPPOSITE (indent side is
            // the finger side), so we push deformation toward the finger side.
            let dirToCenterX = toCenter.dx / dist
            let dirToCenterY = toCenter.dy / dist
            let strength = min(overlap / radius, 1.0)
            targetDeform = CGVector(
                dx: -dirToCenterX * strength * radius * 0.6,
                dy: -dirToCenterY * strength * radius * 0.6
            )
        }

        // Spring-damper on deformation with viscosity slowing the target chase.
        let deformK = elasticity
        let deformC = damping * (1.5 - 0.9 * overshoot)
        let approach = 1.0 - Double(viscosity) * 0.85
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
