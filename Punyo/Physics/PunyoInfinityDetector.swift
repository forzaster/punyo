import Foundation
import CoreGraphics

// Watches the live finger trail and fires once when it draws a ♾️.
//
// A ♾️ has two features that let us recognize it cheaply, without importing
// a whole trajectory pipeline into this branch:
//   1. self-crossing — the two lobes join at one intersection,
//   2. total absolute angle change near two full turns — one loop per lobe,
//      but they go opposite ways so signed winding cancels toward zero.
//
// We keep a rolling window of the last ~1.5 s and re-check on each new
// sample. Both checks have to pass in the same window; either alone
// (a wobble, or a single loop) is not enough.
//
// Bounded buffer so an idle finger can't fill memory. Old samples fall off
// the front — the recent shape is the whole signal.
final class PunyoInfinityDetector {
    private struct Sample { let x: CGFloat; let y: CGFloat; let t: TimeInterval }

    private var samples: [Sample] = []
    private let capacity = 96
    // Only samples within this window contribute — a ♾️ drawn fast is still
    // in the window; a stroke slower than this reads as "not a ♾️" even if
    // the shape works out. Keeps the detector from being fooled by minute-
    // long doodles that happen to loop twice.
    private let windowSeconds: TimeInterval = 1.6
    // Segments closer together than this in time are considered adjacent
    // and can't be crossings — the pen is basically the same point.
    private let adjacentSkip = 3

    var isActive = false

    func begin(at point: CGPoint, time: TimeInterval) {
        samples.removeAll(keepingCapacity: true)
        samples.append(Sample(x: point.x, y: point.y, t: time))
        isActive = true
    }

    // Push a new finger sample and return the ♾️ pose axis if this sample
    // completes a ♾️. Returns nil otherwise. Callers should stop feeding
    // once a pose has been triggered until the touch ends.
    func record(at point: CGPoint, time: TimeInterval) -> CGVector? {
        guard isActive else { return nil }
        if let last = samples.last {
            let dx = point.x - last.x
            let dy = point.y - last.y
            if hypot(dx, dy) < 1.0 { return nil }
        }
        samples.append(Sample(x: point.x, y: point.y, t: time))

        // Drop samples that fell out of the window from the front. Then
        // drop any excess capacity.
        let cutoff = time - windowSeconds
        var head = 0
        while head < samples.count && samples[head].t < cutoff { head += 1 }
        if head > 0 { samples.removeFirst(head) }
        if samples.count > capacity {
            samples.removeFirst(samples.count - capacity)
        }

        return detect()
    }

    func end() {
        isActive = false
        samples.removeAll(keepingCapacity: true)
    }

    // MARK: - Detection

    // Returns the pose axis if the buffered samples form a ♾️. Called on
    // every new sample; must stay cheap. Segment count is bounded by
    // `capacity`, so O(N²) crossings check is fine at these sizes.
    private func detect() -> CGVector? {
        guard samples.count >= 20 else { return nil }

        // Absolute angle change: near 2 full turns = two lobes.
        var totalAbs: Double = 0
        var lastAngle: Double? = nil
        for i in 1..<samples.count {
            let dx = samples[i].x - samples[i - 1].x
            let dy = samples[i].y - samples[i - 1].y
            let d = hypot(dx, dy)
            if d < 0.5 { continue }
            let ang = atan2(Double(dy), Double(dx))
            if let last = lastAngle {
                var da = ang - last
                while da > .pi { da -= 2 * .pi }
                while da < -.pi { da += 2 * .pi }
                totalAbs += abs(da)
            }
            lastAngle = ang
        }
        // ~1.8 turns is the floor — a hand-drawn ♾️ often comes in around
        // 1.9–2.1. Anything much less than that is a single loop or a
        // squiggle.
        if totalAbs < 1.8 * 2 * .pi { return nil }

        // Self-intersection scan. Segments (i, i+1) vs (j, j+1) for j ≥ i+skip.
        // Break out on the first crossing — one is enough for a ♾️; two
        // usually means the finger looped again and we're happy either way.
        let n = samples.count - 1
        for i in 0..<n {
            let ax = samples[i].x, ay = samples[i].y
            let bx = samples[i + 1].x, by = samples[i + 1].y
            let jStart = i + adjacentSkip
            if jStart >= n { break }
            for j in jStart..<n {
                let cx = samples[j].x, cy = samples[j].y
                let dx2 = samples[j + 1].x, dy2 = samples[j + 1].y
                if Self.segmentsCross(ax, ay, bx, by, cx, cy, dx2, dy2) {
                    return principalAxis()
                }
            }
        }
        return nil
    }

    // Standard 2D segment-crossing test via signed areas. Returns true when
    // the two open segments strictly cross. Endpoints touching count as
    // "no cross" so an accidental co-vertex on a hand-drawn stroke doesn't
    // trigger.
    private static func segmentsCross(
        _ ax: CGFloat, _ ay: CGFloat, _ bx: CGFloat, _ by: CGFloat,
        _ cx: CGFloat, _ cy: CGFloat, _ dx: CGFloat, _ dy: CGFloat
    ) -> Bool {
        let d1 = cross(bx - ax, by - ay, cx - ax, cy - ay)
        let d2 = cross(bx - ax, by - ay, dx - ax, dy - ay)
        let d3 = cross(dx - cx, dy - cy, ax - cx, ay - cy)
        let d4 = cross(dx - cx, dy - cy, bx - cx, by - cy)
        return (d1 * d2 < 0) && (d3 * d4 < 0)
    }

    private static func cross(_ ax: CGFloat, _ ay: CGFloat,
                              _ bx: CGFloat, _ by: CGFloat) -> CGFloat {
        ax * by - ay * bx
    }

    // Long axis of the drawn ♾️, via 2×2 PCA on the sample cloud. The two
    // lobes will separate along this direction, so a diagonal ♾️ reads as
    // diagonal on screen instead of getting snapped to horizontal.
    private func principalAxis() -> CGVector {
        guard samples.count >= 2 else { return CGVector(dx: 1, dy: 0) }
        var mx: CGFloat = 0, my: CGFloat = 0
        for s in samples { mx += s.x; my += s.y }
        let n = CGFloat(samples.count)
        mx /= n; my /= n
        var sxx: CGFloat = 0, syy: CGFloat = 0, sxy: CGFloat = 0
        for s in samples {
            let dx = s.x - mx, dy = s.y - my
            sxx += dx * dx
            syy += dy * dy
            sxy += dx * dy
        }
        // Closed-form 2×2 symmetric eigenvector for the larger eigenvalue.
        let tr = sxx + syy
        let det = sxx * syy - sxy * sxy
        let disc = max(0, tr * tr * 0.25 - det)
        let lambda = tr * 0.5 + sqrt(disc)
        let vx = sxy
        let vy = lambda - sxx
        let len = hypot(vx, vy)
        if len < 1e-4 {
            // Degenerate (nearly circular). Fall back to horizontal — an
            // unresolved axis shouldn't block the pose.
            return CGVector(dx: 1, dy: 0)
        }
        return CGVector(dx: vx / len, dy: vy / len)
    }
}
