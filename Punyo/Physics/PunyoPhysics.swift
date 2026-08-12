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

    // Lateral / directional bulge. Meaningful only when the finger is off
    // centre — at the exact centre there is no direction to bulge toward, which
    // is why it cannot be the only deformation channel.
    var deformation: CGVector = .zero
    var deformationVelocity: CGVector = .zero

    // Scalar squash: how flat the body is being pressed, 0 = round, 1 = fully
    // squashed. This is the degree of freedom a float2 bulge cannot express —
    // it peaks exactly where the directional bulge degenerates (finger on the
    // centre) and falls to zero at the rim, so between the two every contact
    // point produces a visible response.
    var squash: CGFloat = 0
    var squashVelocity: CGFloat = 0

    // How far the silhouette spreads radially at squash == 1. The Metal helper
    // `punyoSquashSpread` mirrors this number; anything drawn on top of the
    // shader (the eyes) scales by it so it stays on the body.
    static let squashSpread: CGFloat = 0.28

    // Multiplier the silhouette's axes are scaled by right now. The ceiling is
    // the shader's, matched here deliberately: a hard press can carry `squash`
    // past 1.5 for a frame or two, and if the eyes kept growing after the body
    // had stopped they would walk straight off the face.
    var squashSpread: CGFloat {
        1.0 + PunyoPhysics.squashSpread * max(0, min(1.5, squash))
    }

    // MARK: - Pose (♾️ metaball variant)
    //
    // Separate from the ellipse deformation because it isn't simulated: it's
    // a target the shader honours while the finger holds the pose. The pose
    // owns its own progress + axis; physics owns the step schedule.
    private(set) var infinityPose = PunyoInfinityPose()
    // One-shot event produced when the pose collapses on release. Consumed
    // by whatever handles "one body becoming two".
    private var pendingSplit: PunyoSplitEvent?

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
    // 0...1: how much the finger is actually on the body right now, smoothed.
    private(set) var contactGrip: CGFloat = 0

    private var captureContact: TimeInterval = 0
    private var dazedTimer: TimeInterval = 0
    private var pendingCapture: PunyoCaptureEvent?
    private var touchStartTime: TimeInterval?
    private var captureCount: Int = 0
    private var lastCaptureTime: TimeInterval?

    // Per-touch stats consumed by the gesture recorder at capture. Reset in
    // beginTouch, so a chase that ends in a lift-off (no catch) simply
    // discards them — the recorder is what asks for them, and it only asks
    // on capture.
    private(set) var perTouchDeformationPeak: CGFloat = 0
    // A "missed grab" is a stretch of time inside the grab radius that was
    // interrupted before captureHold elapsed. Only counted once per entry —
    // a jittery finger sitting on the edge does not rack up dozens.
    private(set) var perTouchGrabMisses: Int = 0
    private var wasBuildingCapture: Bool = false

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
    //
    // Both channels count. Combining them in quadrature rather than adding
    // keeps a poke that is both off-centre and deep from pinning the value at
    // 1.0, while a dead-centre press — all squash, no bulge — still produces
    // the haptic it obviously should.
    var deformationLevel: Double {
        let lateral = Double(hypot(deformation.dx, deformation.dy) / (radiusMean * 0.8))
        let scalar = Double(max(0, squash)) * 0.9
        return min(1.0, (lateral * lateral + scalar * scalar).squareRoot())
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

    // 0 -> 1 across [edge0, edge1], flat outside. Used to shape contact
    // responses so they ramp instead of switching.
    private func smoothstep(_ edge0: CGFloat, _ edge1: CGFloat, _ x: CGFloat) -> CGFloat {
        let t = max(0, min(1, (x - edge0) / max(0.0001, edge1 - edge0)))
        return t * t * (3 - 2 * t)
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
        // A chase is one touch: catching it requires lifting off, so the length
        // of this touch is exactly how long the catch took.
        touchStartTime = time
        perTouchDeformationPeak = 0
        perTouchGrabMisses = 0
        wasBuildingCapture = false
    }

    func updateTouch(to point: CGPoint, time: TimeInterval) {
        let dt = max(0.0001, time - lastFingerTime)
        fingerVelocity = CGVector(
            dx: (point.x - lastFingerPosition.x) / CGFloat(dt),
            dy: (point.y - lastFingerPosition.y) / CGFloat(dt)
        )
        // The reference has to advance to the point we just measured against.
        // Carrying the previous `fingerPosition` forward instead would divide a
        // two-frame displacement by a one-frame dt and report roughly double.
        lastFingerPosition = point
        lastFingerTime = time
        fingerPosition = point
    }

    func endTouch(time: TimeInterval) {
        isFingerDown = false
        fingerVelocity = .zero

        // Bounce on release, scaled by how long the touch was held. A brief
        // tap gets a small pop; a sustained hold launches the puni upward
        // with a lively bounce that the settle spring then reels back in.
        if let start = touchStartTime {
            let held = max(0.0, time - start)
            // Saturates near 1.2 s: past that, holding longer doesn't keep
            // stacking energy — the bounce reads as "as much as it can hold".
            let strength = CGFloat(min(1.0, held / 1.2))
            let baseKick: CGFloat = 90
            let peakKick: CGFloat = 520
            let kick = baseKick + (peakKick - baseKick) * strength
            velocity.dy -= kick
        }
        touchStartTime = nil
    }

    // One-shot event for the moment of capture, consumed by whatever reacts to
    // it (haptics, speech).
    func consumeCapture() -> PunyoCaptureEvent? {
        defer { pendingCapture = nil }
        return pendingCapture
    }

    // MARK: - Pose control

    // Called by the gesture detector when a ♾️ trace is recognized. Axis is
    // the direction the two lobes will separate along — typically the long
    // axis of the drawn loop, but we keep it caller-supplied so any future
    // pose can pick its own spine.
    func beginInfinityPose(axis: CGVector) {
        let len = hypot(axis.dx, axis.dy)
        infinityPose.axis = len > 0.0001
            ? CGVector(dx: axis.dx / len, dy: axis.dy / len)
            : CGVector(dx: 1, dy: 0)
        infinityPose.target = 1
    }

    // Ends the pose. If it was engaged (fully entered), the collapse queues a
    // split event for the caller to hand off to the split/merge system. If it
    // never fully engaged, it just collapses silently.
    func endInfinityPose(params: PunyoParameters) {
        let wasEngaged = infinityPose.isEngaged
        infinityPose.target = 0
        if wasEngaged {
            queueSplit(params: params)
        }
    }

    // Poll for a pending split. Consumed once; caller decides what to do
    // (spawn two bodies, log it, whatever).
    func consumeSplit() -> PunyoSplitEvent? {
        defer { pendingSplit = nil }
        return pendingSplit
    }

    // Snapshot of where the two lobes are right now, in world coordinates.
    // Derived from center + eased spacing along the pose axis. Rendered by
    // the metaball shader; also the source of truth for a split event.
    func infinityLobeCenters(params: PunyoParameters) -> (CGPoint, CGPoint) {
        let spacing = infinityLobeSpacing(params: params)
            * CGFloat(infinityPose.progress)
        let ax = infinityPose.axis
        let half = spacing * 0.5
        let a = CGPoint(x: center.x - ax.dx * half,
                        y: center.y - ax.dy * half)
        let b = CGPoint(x: center.x + ax.dx * half,
                        y: center.y + ax.dy * half)
        return (a, b)
    }

    // Full separation (progress==1) between the two lobe centers, in points.
    // Kept public so the shader marshaller and the debug readout agree.
    func infinityLobeSpacing(params: PunyoParameters) -> CGFloat {
        radiusMean * CGFloat(params.infinitySpacing)
    }

    // Lobe radius derived from the mean body radius. Constant across the two
    // lobes — the "big two" case. A third pinch lobe (small) is derived from
    // this in the shader if we later expose it.
    func infinityLobeRadius(params: PunyoParameters) -> CGFloat {
        radiusMean * CGFloat(params.infinityRadius)
    }

    private func queueSplit(params: PunyoParameters) {
        let (a, b) = infinityLobeCenters(params: params)
        pendingSplit = PunyoSplitEvent(
            lobeA: a, lobeB: b,
            radius: infinityLobeRadius(params: params),
            axis: infinityPose.axis
        )
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

        updateCapture(fingerDist: fingerDist, time: time, dt: elapsed)

        let depth = isFingerDown ? contactDepth(from: fingerPosition) : 0
        updateContactGrip(depth: depth, dt: dt)

        // Threat falls off to nothing at fleeRadius. A captured or freshly
        // released puni has no threat: caught means caught, and the beat after
        // release is spent dazed rather than instantly bolting again.
        if isFingerDown && !isCaptured && dazedTimer <= 0 {
            let byDistance = max(0, min(1, 1 - fingerDist / fleeRadius))
            // Contact beats flight. A finger that has actually landed inside
            // the silhouette is a poke, and a poke has to register as one —
            // otherwise the body slides out from under it before the springs
            // can build and nothing visible happens at all. The chase is still
            // the entire behaviour for a finger that is near but not on it,
            // which is where it always mattered.
            threat = Double(byDistance * (1 - contactGrip))
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
                         depth: depth,
                         dt: dt)

        applySquash(elasticity: elasticity,
                    damping: damping,
                    viscosity: viscosity,
                    overshoot: overshoot,
                    squashiness: CGFloat(params.squashiness),
                    depth: depth,
                    dt: dt)

        // Sampled after both deformation channels update so a slam that lands
        // on this frame still counts. Only tracked while the finger is on the
        // puni — rebounds after release aren't part of "how it was caught".
        //
        // Both channels feed it, in quadrature and in point units, with the
        // same relative weighting `deformationLevel` uses. A dead-centre press
        // is nearly all squash and almost no lateral bulge, so sampling the
        // vector alone would hand the speech layer a feather touch for what
        // was actually the hardest poke available.
        if isFingerDown {
            let lateral = hypot(deformation.dx, deformation.dy)
            let scalar = max(0, squash) * radiusMean * 0.72
            let mag = (lateral * lateral + scalar * scalar).squareRoot()
            if mag > perTouchDeformationPeak { perTouchDeformationPeak = mag }
        }

        // Pose easing is decoupled from all the spring math — it just moves
        // toward target on its own schedule. Also runs the "threshold floor
        // means split now" check while the pose is engaged, so pushing the
        // slider into a shattered field commits the split rather than
        // showing a broken silhouette.
        infinityPose.step(dt: elapsed)
        if infinityPose.isEngaged &&
           params.infinityThreshold <= PunyoParameters.infinityThresholdFloor + 1e-4 {
            endInfinityPose(params: params)
        }
    }

    // Damping as a fraction of critical for the given stiffness. Expressing it
    // this way is what stops the contact transient from blowing past the target:
    // a fixed absolute damping left a stiff spring wildly underdamped, which is
    // how a 77pt target used to peak at 182pt. `overshoot` now buys a real,
    // bounded amount of bounce, and `damping` scales that around its default.
    private func criticalDamping(
        stiffness: CGFloat,
        damping: CGFloat,
        overshoot: CGFloat
    ) -> CGFloat {
        // Roughly: overshoot 0 is dead flat, 0.5 gives a single visible bounce,
        // 1.0 wobbles. Damping scales that around its own default.
        let zeta = (0.92 - 0.72 * overshoot) * max(0.30, min(1.8, damping / 8.0))
        return 2 * (stiffness.squareRoot()) * zeta
    }

    // MARK: - Pieces

    // How firmly the finger currently has it, 0...1. Grabs almost instantly and
    // lets go slowly. The asymmetry is the point: a poke near the rim only has
    // to nudge the body a pixel to fall out of contact, and without the slow
    // release that would make it flee harder, lose contact further, and bolt —
    // a runaway that reads on screen as the touch simply not registering.
    private func updateContactGrip(depth: CGFloat, dt: CGFloat) {
        let onBody = smoothstep(0, 0.06, depth)
        let rate: CGFloat = onBody > contactGrip ? 30.0 : 3.0
        contactGrip += (onBody - contactGrip) * min(1, rate * dt)
    }

    private func updateCapture(fingerDist: CGFloat, time: TimeInterval, dt: TimeInterval) {
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
            wasBuildingCapture = true
            if captureContact >= captureHold {
                isCaptured = true
                captureContact = 0
                wasBuildingCapture = false
                captureCount += 1
                pendingCapture = PunyoCaptureEvent(
                    stamina: stamina,
                    chaseDuration: touchStartTime.map { time - $0 } ?? 0,
                    captureCount: captureCount,
                    timeSinceLastCapture: lastCaptureTime.map { time - $0 }
                )
                lastCaptureTime = time
            }
        } else {
            // Finger slid off before the hold window closed: that's one
            // fumble. Guarded by wasBuildingCapture so a finger that never
            // touched the body doesn't get counted.
            if wasBuildingCapture {
                perTouchGrabMisses += 1
            }
            captureContact = 0
            wasBuildingCapture = false
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
        depth: CGFloat,
        dt: CGFloat
    ) {
        // Target deformation vector: from finger toward center, magnitude grows as
        // finger overlaps body. Viscosity controls how "sticky/slow" the deform target
        // is pursued.
        //
        // This channel is the *lateral* squeeze, so it is weighted by how far
        // off centre the finger is: right in the middle there is no lateral
        // direction to speak of and `squash` carries the whole response, while
        // a poke near the rim is almost all sideways bulge.
        var targetDeform = CGVector.zero
        if depth > 0.001 {
            let fromFinger = CGVector(dx: center.x - fingerPosition.x,
                                      dy: center.y - fingerPosition.y)
            let distance = hypot(fromFinger.dx, fromFinger.dy)
            if distance > 0.0001 {
                // 0 at the centre, 1 once the finger is a good way out. Kills
                // the direction singularity instead of dividing through it.
                let lateral = smoothstep(0, radiusMean * 0.45, distance)
                let magnitude = depth * lateral * radiusMean * 0.62
                targetDeform = CGVector(
                    dx: fromFinger.dx / distance * magnitude,
                    dy: fromFinger.dy / distance * magnitude
                )
            }
        }

        let deformK = elasticity * 1.4
        let deformC = criticalDamping(stiffness: deformK,
                                      damping: damping,
                                      overshoot: overshoot)
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

    // The scalar half of the deformation: how flat the body is pressed. Peaks
    // with the finger on the centre and falls to zero at the rim, so it covers
    // exactly the contacts the directional bulge cannot.
    private func applySquash(
        elasticity: CGFloat,
        damping: CGFloat,
        viscosity: CGFloat,
        overshoot: CGFloat,
        squashiness: CGFloat,
        depth: CGFloat,
        dt: CGFloat
    ) {
        // Shaped rather than raw: a shallow contact near the rim still reads as
        // a real press, but the falloff to the boundary stays monotone.
        let shaped = depth > 0.001 ? pow(depth, 0.6) : 0
        var target = shaped * squashiness

        // Being held is being squeezed. Capture drags the body onto the finger,
        // so depth is already near 1 while captured — this just puts a floor
        // under it so the grip reads as a grip even mid-transit.
        if isCaptured {
            target = max(target, 0.65 * squashiness)
        }

        // Stiffer than the lateral channel and damped a touch harder: a scalar
        // that pumps up and down is the one thing that would read as buzzing
        // rather than as a squish, so this settles rather than oscillating.
        let squashK = elasticity * 1.8
        let squashC = criticalDamping(stiffness: squashK,
                                      damping: damping,
                                      overshoot: overshoot * 0.55)
        let approach = 1.0 - viscosity * 0.45
        let effectiveTarget = squash + (target - squash) * approach
        // Divided damping, same as the lateral channel and for the same reason:
        // a late frame has to cost accuracy, not stability.
        squashVelocity = (squashVelocity + squashK * (effectiveTarget - squash) * dt)
            / (1 + squashC * dt)
        squash += squashVelocity * dt
        // Never invert: a negative squash would inflate the silhouette and read
        // as the body swelling when you let go.
        if squash < 0 {
            squash = 0
            squashVelocity = max(0, squashVelocity)
        }
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
