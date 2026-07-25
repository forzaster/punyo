import Foundation
import CoreGraphics
import Observation

@Observable
final class PunyoPhysics {
    // MARK: - Body

    var center: CGPoint = .zero
    var restCenter: CGPoint = .zero
    var velocity: CGVector = .zero
    // Play area used to keep the puni on screen while it runs around.
    var bounds: CGSize = .zero

    var deformation: CGVector = .zero
    var deformationVelocity: CGVector = .zero

    // MARK: - Touch

    var isFingerDown: Bool = false
    var fingerPosition: CGPoint = .zero
    private var lastFingerPosition: CGPoint = .zero
    private var lastFingerTime: TimeInterval = 0
    var fingerVelocity: CGVector = .zero

    // MARK: - Chase state

    // 1 = fresh, 0 = worn out. Drains while running from the finger, refills
    // while left alone. Everything about being catchable hangs off this.
    var stamina: Double = 1.0
    var isCaptured: Bool = false
    // How urgently it wants to get away right now (0...1).
    private(set) var threat: Double = 0.0

    private var captureContact: TimeInterval = 0
    private var dazedTimer: TimeInterval = 0
    private var pendingCapturePop = false

    private var lastStepTime: TimeInterval?

    // Slightly wider than tall gives the puni a softer, characterful silhouette.
    let radiusX: CGFloat = 100
    let radiusY: CGFloat = 82
    var radiusMean: CGFloat { (radiusX + radiusY) * 0.5 }

    // Zones, in body radii.
    private var fleeRadius: CGFloat { radiusMean * 2.0 }
    private var captureRadius: CGFloat { radiusMean * 0.5 }
    private var curiosityRadius: CGFloat { radiusMean * 3.6 }
    private let captureHold: TimeInterval = 0.10
    private let dazedDuration: TimeInterval = 0.55

    // Normalized 0..1 measure of how much the puni is currently deformed.
    // Used to drive continuous haptics intensity.
    var deformationLevel: Double {
        let mag = hypot(deformation.dx, deformation.dy)
        let scale = radiusMean * 0.8
        return Double(min(1.0, mag / scale))
    }

    var deformationMagnitude: CGFloat {
        hypot(deformation.dx, deformation.dy)
    }

    // 0 at the ellipse boundary and 1 at its center.
    private func contactDepth(from point: CGPoint) -> CGFloat {
        let dx = (point.x - center.x) / radiusX
        let dy = (point.y - center.y) / radiusY
        return max(0, 1 - hypot(dx, dy))
    }

    // MARK: - Input

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
            dx: (point.x - lastFingerPosition.x) / CGFloat(dt),
            dy: (point.y - lastFingerPosition.y) / CGFloat(dt)
        )
        lastFingerPosition = fingerPosition
        lastFingerTime = time
        fingerPosition = point
    }

    func endTouch() {
        isFingerDown = false
        fingerVelocity = .zero
    }

    // One-shot flag for the moment of capture, consumed by the haptics driver.
    func consumeCapturePop() -> Bool {
        guard pendingCapturePop else { return false }
        pendingCapturePop = false
        return true
    }

    // MARK: - Simulation

    func step(time: TimeInterval, params: PunyoParameters) {
        defer { lastStepTime = time }
        guard let last = lastStepTime else { return }
        let elapsed = min(1.0 / 30.0, max(0.0, time - last))
        if elapsed == 0 { return }

        // Geometry is CGFloat throughout; parameters are converted once here so
        // no expression below mixes CGFloat and Double.
        let dt = CGFloat(elapsed)
        let elasticity = CGFloat(params.elasticity)
        let damping = CGFloat(params.damping)
        let viscosity = CGFloat(params.viscosity)
        let overshoot = CGFloat(params.overshoot)

        let toFinger = CGVector(dx: fingerPosition.x - center.x,
                                dy: fingerPosition.y - center.y)
        let fingerDist = hypot(toFinger.dx, toFinger.dy)

        updateCapture(fingerDist: fingerDist, dt: elapsed)

        // Threat falls off to nothing at fleeRadius. A captured or freshly
        // released puni has no threat: caught means caught, and the beat after
        // release is spent dazed rather than instantly bolting again.
        if isFingerDown && !isCaptured && dazedTimer <= 0 {
            threat = Double(max(0, min(1, 1 - fingerDist / fleeRadius)))
        } else {
            threat = 0
        }
        let threatC = CGFloat(threat)

        updateStamina(params: params, dt: elapsed)

        applyFlee(time: time,
                  toFinger: toFinger,
                  fingerDist: fingerDist,
                  fleeSpeed: CGFloat(params.fleeSpeed),
                  threat: threatC,
                  dt: dt)

        // --- Body translation ---
        // Home spring and damping both fade out under threat, so a fleeing puni
        // isn't fighting its own leash. With the finger gone they come back in
        // full and produce the wobble-home settle.
        var springTarget = restCenter
        var springK = elasticity * 0.15 * (1.0 - 0.85 * threatC)
        if isCaptured {
            // Held in hand: the follow behaviour, still weighed down by viscosity.
            springTarget = fingerPosition
            springK = elasticity * 0.55 * (1.0 - viscosity * 0.75)
        }
        let bodyC = damping * (1.0 - 0.7 * overshoot) * (1.0 - 0.75 * threatC)
        let toTarget = CGVector(dx: springTarget.x - center.x,
                                dy: springTarget.y - center.y)
        var ax = springK * toTarget.dx - bodyC * velocity.dx
        var ay = springK * toTarget.dy - bodyC * velocity.dy

        // Curiosity: back off far enough and it drifts toward you. This is what
        // keeps fleeing from reading as pure rejection.
        if isFingerDown && !isCaptured && fingerDist > curiosityRadius {
            let pull = CGFloat(params.curiosity) * 260.0
            ax += toFinger.dx / fingerDist * pull
            ay += toFinger.dy / fingerDist * pull
        }

        velocity.dx += ax * dt
        velocity.dy += ay * dt
        center.x += velocity.dx * dt
        center.y += velocity.dy * dt
        clampToBounds()

        applyDeformation(elasticity: elasticity,
                         damping: damping,
                         viscosity: viscosity,
                         overshoot: overshoot,
                         dt: dt)
    }

    // MARK: - Pieces

    private func updateCapture(fingerDist: CGFloat, dt: TimeInterval) {
        if dazedTimer > 0 {
            dazedTimer = max(0, dazedTimer - dt)
        }

        guard isFingerDown else {
            if isCaptured {
                isCaptured = false
                dazedTimer = dazedDuration
            }
            captureContact = 0
            return
        }

        // Held until you let go.
        if isCaptured { return }

        // A tired puni can't wriggle out of a grip that isn't quite centred, so
        // the window you have to hit widens as it wears down. This is the main
        // way fatigue pays off for the player.
        let grabRadius = captureRadius * (1.0 + 0.5 * CGFloat(1.0 - stamina))
        if fingerDist < grabRadius {
            captureContact += dt
            if captureContact >= captureHold {
                isCaptured = true
                pendingCapturePop = true
                captureContact = 0
            }
        } else {
            captureContact = 0
        }
    }

    private func updateStamina(params: PunyoParameters, dt: TimeInterval) {
        let fatigue = params.fatigue
        if isCaptured {
            // Struggling in your hand costs it something too.
            stamina -= fatigue * 0.7 * dt
        } else if threat > 0.05 {
            stamina -= fatigue * threat * dt
        } else {
            // Catching its breath: slower than the drain, so a sustained chase
            // always wins eventually.
            stamina += fatigue * 0.45 * dt
        }
        stamina = min(1.0, max(0.0, stamina))
    }

    private func applyFlee(
        time: TimeInterval,
        toFinger: CGVector,
        fingerDist: CGFloat,
        fleeSpeed: CGFloat,
        threat: CGFloat,
        dt: CGFloat
    ) {
        guard threat > 0.001, fingerDist > 0.0001 else { return }

        // Effort collapses as it tires but never reaches zero — an exhausted
        // puni still twitches away, it just can't outrun a finger any more.
        let effort = CGFloat(0.25 + 0.75 * stamina)

        let awayX = -toFinger.dx / fingerDist
        let awayY = -toFinger.dy / fingerDist
        // A sideways swerve keeps it from running dead-straight into a wall, and
        // reads as dodging rather than sliding.
        let swerve = CGFloat(sin(time * 3.1) * 0.45)
        let dirX = awayX - awayY * swerve
        let dirY = awayY + awayX * swerve
        let dirLen = max(0.0001, hypot(dirX, dirY))

        let target = fleeSpeed * threat * effort
        let desiredX = dirX / dirLen * target
        let desiredY = dirY / dirLen * target
        // Velocity tracking rather than a force, so the slider keeps reading as
        // a speed instead of an acceleration.
        let response = min(1.0, 12.0 * dt)
        velocity.dx += (desiredX - velocity.dx) * response
        velocity.dy += (desiredY - velocity.dy) * response
    }

    private func applyDeformation(
        elasticity: CGFloat,
        damping: CGFloat,
        viscosity: CGFloat,
        overshoot: CGFloat,
        dt: CGFloat
    ) {
        // Target deformation vector: from finger toward center, magnitude grows as
        // finger overlaps body. Viscosity controls how "sticky/slow" the deform target
        // is pursued.
        var targetDeform = CGVector.zero
        let depth = isFingerDown ? contactDepth(from: fingerPosition) : 0
        if depth > 0.001 {
            let fromFinger = CGVector(dx: center.x - fingerPosition.x,
                                      dy: center.y - fingerPosition.y)
            let distance = max(0.0001, hypot(fromFinger.dx, fromFinger.dy))
            let dirBulgeX = fromFinger.dx / distance
            let dirBulgeY = fromFinger.dy / distance
            targetDeform = CGVector(
                dx: dirBulgeX * depth * radiusMean * 0.85,
                dy: dirBulgeY * depth * radiusMean * 0.85
            )
        }

        let deformK = elasticity * 1.4
        let deformC = damping * (1.15 - 0.85 * overshoot)
        let approach = 1.0 - viscosity * 0.45
        let effectiveTargetX = deformation.dx + (targetDeform.dx - deformation.dx) * approach
        let effectiveTargetY = deformation.dy + (targetDeform.dy - deformation.dy) * approach
        let dax = deformK * (effectiveTargetX - deformation.dx) - deformC * deformationVelocity.dx
        let day = deformK * (effectiveTargetY - deformation.dy) - deformC * deformationVelocity.dy
        deformationVelocity.dx += dax * dt
        deformationVelocity.dy += day * dt
        deformation.dx += deformationVelocity.dx * dt
        deformation.dy += deformationVelocity.dy * dt
    }

    private func clampToBounds() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let margin = radiusMean * 0.7
        let bounce: CGFloat = 0.5
        if center.x < margin {
            center.x = margin
            velocity.dx = abs(velocity.dx) * bounce
        }
        if center.x > bounds.width - margin {
            center.x = bounds.width - margin
            velocity.dx = -abs(velocity.dx) * bounce
        }
        if center.y < margin {
            center.y = margin
            velocity.dy = abs(velocity.dy) * bounce
        }
        if center.y > bounds.height - margin {
            center.y = bounds.height - margin
            velocity.dy = -abs(velocity.dy) * bounce
        }
    }
}
