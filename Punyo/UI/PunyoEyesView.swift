import SwiftUI

// Two cute eyes rendered on top of the puni. Drawn with Canvas rather than
// bitmap assets so they scale cleanly and don't need image resources — the
// eye is composed procedurally each frame (white sclera + follow pupil +
// specular highlight), which reads on-screen the same as a small texture
// pasted onto the body.
//
// The pupils track the finger while a touch is active, drift slightly with
// deformation so the eyes wobble with the body, and blink on a slow cycle
// with a brief squint pass every few seconds.
struct PunyoEyesView: View {
    let physics: PunyoPhysics

    var body: some View {
        TimelineView(.animation) { context in
            let now = context.date.timeIntervalSinceReferenceDate
            Canvas { ctx, _ in
                draw(ctx: ctx, time: now)
            }
            .allowsHitTesting(false)
        }
    }

    private func draw(ctx: GraphicsContext, time: TimeInterval) {
        let c = physics.center
        // Bail while the physics hasn't been positioned yet (before onAppear
        // has laid down bounds and rest center). Drawing at (0, 0) would slap
        // a pair of eyes into the top-left corner for one frame.
        guard c != .zero else { return }

        // Squash spreads the silhouette radially in the shader, so the face has
        // to spread with it — otherwise a good hard press slides the eyes off
        // the body. Same factor the Metal helper uses.
        let spread = physics.squashSpread
        let axes = CGSize(width: physics.radiusX * spread,
                          height: physics.radiusY * spread)
        // Upper half of the ellipse, symmetric about the vertical axis. These
        // fractions are the "face layout": pinning them to the axes lets the
        // eyes stay in place if the silhouette ever changes size.
        let eyeOffsetX = axes.width * 0.38
        let eyeOffsetY = axes.height * 0.18
        // The eyes themselves don't inflate — only their placement follows the
        // body, so a squashed puni reads as wide-eyed rather than zoomed in.
        let whiteRadius = min(physics.radiusX, physics.radiusY) * 0.20
        let pupilRadius = whiteRadius * 0.55
        let highlightRadius = whiteRadius * 0.16

        // Eyes ride the deformation just a little so they wobble with the body
        // instead of feeling glued to a rigid transform.
        let wobble = CGSize(width: physics.deformation.dx * 0.12,
                            height: physics.deformation.dy * 0.12)

        let leftEye = CGPoint(x: c.x - eyeOffsetX + wobble.width,
                              y: c.y - eyeOffsetY + wobble.height)
        let rightEye = CGPoint(x: c.x + eyeOffsetX + wobble.width,
                               y: c.y - eyeOffsetY + wobble.height)

        // Blink: two tight closes per ~5s cycle. The eye lid draws as a thin
        // ellipse squashed to a slit, so it reads as a real blink instead of
        // suddenly missing eyes.
        let blinkPhase = time.truncatingRemainder(dividingBy: 5.0)
        let blink: Double = {
            let closeAt = 4.7
            let closeDur = 0.14
            if blinkPhase >= closeAt && blinkPhase < closeAt + closeDur {
                // triangular open→closed→open across the window
                let local = (blinkPhase - closeAt) / closeDur
                return 1.0 - abs(local - 0.5) * 2.0
            }
            return 0.0
        }()

        drawEye(ctx: ctx, center: leftEye, whiteR: whiteRadius,
                pupilR: pupilRadius, highlightR: highlightRadius,
                pupilOffset: pupilOffset(for: leftEye, whiteR: whiteRadius,
                                         pupilR: pupilRadius),
                blink: blink)
        drawEye(ctx: ctx, center: rightEye, whiteR: whiteRadius,
                pupilR: pupilRadius, highlightR: highlightRadius,
                pupilOffset: pupilOffset(for: rightEye, whiteR: whiteRadius,
                                         pupilR: pupilRadius),
                blink: blink)
    }

    // Pupil look direction: toward the finger while it's on screen, or a
    // faint downward gaze at rest so the puni doesn't feel like it's staring
    // straight through the viewer.
    private func pupilOffset(for eye: CGPoint,
                             whiteR: CGFloat,
                             pupilR: CGFloat) -> CGVector {
        let maxOffset = whiteR - pupilR
        if physics.isFingerDown {
            let toFinger = CGVector(dx: physics.fingerPosition.x - eye.x,
                                    dy: physics.fingerPosition.y - eye.y)
            let dist = max(1, hypot(toFinger.dx, toFinger.dy))
            // Ease with distance: nearby fingers park the pupil at the rim;
            // far fingers stay tracked but don't over-drift.
            let reach = min(1.0, dist / (whiteR * 6))
            return CGVector(dx: toFinger.dx / dist * maxOffset * reach,
                            dy: toFinger.dy / dist * maxOffset * reach)
        }
        return CGVector(dx: 0, dy: maxOffset * 0.15)
    }

    private func drawEye(ctx: GraphicsContext,
                         center: CGPoint,
                         whiteR: CGFloat,
                         pupilR: CGFloat,
                         highlightR: CGFloat,
                         pupilOffset: CGVector,
                         blink: Double) {
        // Blink is a vertical squash: 0 = open, 1 = closed to a slit.
        // Everything on the eye scales along y by (1 - blink), so pupil and
        // highlight ride the lid down instead of getting clipped off.
        let openness = max(0.05, 1.0 - CGFloat(blink))
        let whiteRY = whiteR * openness

        // Sclera: soft off-white so it doesn't clip against pale materials.
        let whiteRect = CGRect(x: center.x - whiteR, y: center.y - whiteRY,
                               width: whiteR * 2, height: whiteRY * 2)
        ctx.fill(Path(ellipseIn: whiteRect),
                 with: .color(Color(red: 0.98, green: 0.98, blue: 0.96)))

        // A hair of shadow inside the top of the sclera sells the eyeball as
        // a rounded sphere rather than a flat sticker.
        var shadow = ctx
        shadow.opacity = 0.18
        shadow.clip(to: Path(ellipseIn: whiteRect))
        let shadowRect = whiteRect.offsetBy(dx: 0, dy: -whiteRY * 0.5)
        shadow.fill(Path(ellipseIn: shadowRect), with: .color(.black))

        // Pupil, squashed in step with the sclera so the blink reads clean.
        let pupilCenter = CGPoint(x: center.x + pupilOffset.dx,
                                  y: center.y + pupilOffset.dy * openness)
        let pupilRect = CGRect(x: pupilCenter.x - pupilR,
                               y: pupilCenter.y - pupilR * openness,
                               width: pupilR * 2, height: pupilR * 2 * openness)
        ctx.fill(Path(ellipseIn: pupilRect),
                 with: .color(Color(red: 0.06, green: 0.05, blue: 0.10)))

        // Highlight — a small offset spec dot so the pupil catches "light"
        // from the upper left, matching the shader's L direction. Hidden while
        // the eye is closed so it doesn't sit on top of a slit.
        if openness > 0.4 {
            let hlCenter = CGPoint(x: pupilCenter.x - pupilR * 0.35,
                                   y: pupilCenter.y - pupilR * openness * 0.4)
            let hlRect = CGRect(x: hlCenter.x - highlightR,
                                y: hlCenter.y - highlightR * openness,
                                width: highlightR * 2,
                                height: highlightR * 2 * openness)
            ctx.fill(Path(ellipseIn: hlRect),
                     with: .color(.white.opacity(0.95)))
        }
    }
}
