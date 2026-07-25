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

    // Ellipse silhouette: slightly wider than tall reads as "puni puni".
    let radiusX: CGFloat = 100
    let radiusY: CGFloat = 82

    // Used everywhere a single "characteristic size" is needed
    // (deformation cap, haptics normalization, etc.).
    var radiusMean: CGFloat { (radiusX + radiusY) * 0.5 }

    // Normalized 0..1 measure of how much the puni is currently deformed.
    // Used to drive continuous haptics intensity.
    var deformationLevel: Double {
        let mag = hypot(deformation.dx, deformation.dy)
        let scale = radiusMean * 0.8
        return min(1.0, mag / scale)
    }

    var deformationMagnitude: CGFloat {
        hypot(deformation.dx, deformation.dy)
    }

    // Ellipse containment: (dx/rx)^2 + (dy/ry)^2 <= 1. Returned value is a
    // 0..1 "contact depth" that ramps from 0 at the boundary to 1 near center.
    private func contactDepth(from point: CGPoint) -> Double {
        let dx = (point.x - center.x) / radiusX
        let dy = (point.y - center.y) / radiusY
        let n2 = Double(dx * dx + dy * dy)
        return max(0.0, 1.0 - sqrt(n2))
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

        // --- Body translation: rest spring + contact-gated finger follow ---
        let toRest = CGVector(dx: restCenter.x - center.x,
                              dy: restCenter.y - center.y)
        var followForce = CGVector.zero
        let depth = isFingerDown ? contactDepth(from: fingerPosition) : 0.0
        if depth > 0.001 {
            let toFinger = CGVector(dx: fingerPosition.x - center.x,
                                    dy: fingerPosition.y - center.y)
            let followScale = 1.0 - viscosity * 0.6
            let followK = elasticity * 0.6 * followScale * depth
            followForce = CGVector(dx: followK * toFinger.dx,
                                   dy: followK * toFinger.dy)
        }

        let restK = elasticity * 0.15
        let bodyC = damping * (1.0 - 0.7 * overshoot)
        let ax = restK * toRest.dx + followForce.dx - bodyC * velocity.dx
        let ay = restK * toRest.dy + followForce.dy - bodyC * velocity.dy
        velocity.dx += ax * dt
        velocity.dy += ay * dt
        center.x += velocity.dx * dt
        center.y += velocity.dy * dt

        // --- Deformation: mass pushed away from finger --------------------
        var targetDeform = CGVector.zero
        if depth > 0.001 {
            let fromFinger = CGVector(dx: center.x - fingerPosition.x,
                                      dy: center.y - fingerPosition.y)
            let dist = max(0.0001, hypot(fromFinger.dx, fromFinger.dy))
            let dirBulgeX = fromFinger.dx / dist
            let dirBulgeY = fromFinger.dy / dist
            // Bigger silhouette displacement than before → more "puni" wobble.
            let amp = radiusMean * 0.85
            targetDeform = CGVector(
                dx: dirBulgeX * depth * amp,
                dy: dirBulgeY * depth * amp
            )
        }

        // Viscosity mostly affects target lag: lower = snappier chase.
        let deformK = elasticity * 1.4
        let deformC = damping * (1.15 - 0.85 * overshoot)
        let approach = 1.0 - Double(viscosity) * 0.45
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
