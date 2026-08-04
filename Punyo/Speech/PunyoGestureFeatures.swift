import Foundation
import CoreGraphics

// Numeric summary of one chase — from the first sample after touch-down to the
// moment the puni is caught. The whole point of phase 5 is that speech reads
// *how* it was caught, not what: everything below is a knob for that reading.
// Raw sample coordinates never leave the recorder; only these numbers do.
struct PunyoGestureFeatures {
    // --- Trajectory (finger path) ---

    // Path length: how far the finger travelled cumulatively (px).
    let totalDistance: CGFloat
    // Straight-line distance between where the touch started and where it
    // caught (px). netDisplacement / totalDistance is straightness.
    let netDisplacement: CGFloat
    // Time between touch-down and catch (s). Same value the physics reports
    // as chaseDuration; recorded again here so features are self-contained.
    let elapsed: TimeInterval

    // Speeds computed from consecutive samples, in px/s. Peak is what reads
    // as "slammed", mean as "hurried".
    let meanSpeed: CGFloat
    let peakSpeed: CGFloat
    // Absolute change of speed between samples, per second. High peak = sharp
    // yank, low mean with high peak = one flick in a slow drag.
    let peakAcceleration: CGFloat

    // Small back-and-forth. 0 = smooth, ~1 = shaking. Counts direction
    // reversals normalized by number of samples.
    let jitter: Double
    // Mean absolute turning rate along the path (rad / px). High = wiggly,
    // near 0 = a straight line.
    let curvature: Double
    // Signed winding, in whole turns. +1.0 = one loop counter-clockwise. The
    // sign is what distinguishes "ぐるぐる" from a zig-zag with the same
    // curvature.
    let windings: Double
    // netDisplacement / totalDistance, 0…1. 1 = perfectly straight.
    let straightness: Double
    // Bounding-box area of the path (px²). Distinguishes a big loop from a
    // small tremor with the same curvature.
    let boundingArea: CGFloat

    // --- Touch-scoped (from physics) ---

    // How many times the finger entered the grab radius but drifted out
    // before the hold window closed. High count reads as "fumbled".
    let grabMissCount: Int
    // Peak deformation magnitude during this touch. Drives volume/tone —
    // a soft tap and a slam produce very different values even when
    // the trajectory looks similar.
    let deformationPeak: CGFloat
    // deformationPeak divided by the body's mean radius, 0…~1. Kept
    // pre-normalized so descriptors don't have to know the radius.
    let deformationRatio: Double

    static let empty = PunyoGestureFeatures(
        totalDistance: 0, netDisplacement: 0, elapsed: 0,
        meanSpeed: 0, peakSpeed: 0, peakAcceleration: 0,
        jitter: 0, curvature: 0, windings: 0, straightness: 1, boundingArea: 0,
        grabMissCount: 0, deformationPeak: 0, deformationRatio: 0
    )
}
