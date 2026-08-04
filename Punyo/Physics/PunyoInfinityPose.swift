import Foundation
import CoreGraphics

// The ♾️ pose. Not a physical simulation — the spec is explicit that a viscous
// blob can't hold an 8 by itself. Instead: two (optionally three) metaball
// lobes on a spine, eased between "collapsed to one point" and "held apart",
// rendered as a single field so the constriction reads as one thing.
//
// `progress` is the eased parameter; `target` is where we're heading (1 while
// holding, 0 while collapsing). Position along the spine is derived at render
// time, so the shader always sees a coherent snapshot.
struct PunyoInfinityPose {
    // 0 = collapsed on center, 1 = fully separated ♾️.
    var progress: Double = 0
    var target: Double = 0
    // Unit vector along the spine — the axis the two lobes separate along.
    // Locked in when the pose starts, so a wobbling finger doesn't spin the
    // pose around the center.
    var axis: CGVector = CGVector(dx: 1, dy: 0)

    // Whether progress is above the "visible" threshold — used to gate the
    // metaball shader on/off and to short-circuit the ellipse renderer.
    var isVisible: Bool { progress > 0.01 }
    // Fully committed to the pose. Only when true do we treat a finger lift
    // as an intentional split.
    var isEngaged: Bool { target >= 0.999 }

    // Time constant of the ease. ~0.1 s tau gives a settled feel in the
    // 0.3–0.5 s the spec calls for. Kept as an explicit knob so it's obvious
    // where to twist if the transition feels slow or jumpy.
    static let tau: TimeInterval = 0.10

    // Advance progress toward target with an exponential ease. Frame-rate
    // independent because the alpha is derived from dt.
    mutating func step(dt: TimeInterval) {
        guard dt > 0 else { return }
        let alpha = 1.0 - exp(-dt / Self.tau)
        progress += (target - progress) * alpha
    }
}

// Emitted when the pose collapses on release (or when the neck falls below
// the safe threshold). Two lobe centers + a shared radius: enough for a
// future split/merge system to spawn independent bodies. Consumed once —
// the physics clears its pending event after handing it off.
struct PunyoSplitEvent {
    let lobeA: CGPoint
    let lobeB: CGPoint
    let radius: CGFloat
    let axis: CGVector
}
