import Foundation
import CoreGraphics

// Consumes finger samples during one touch and turns them into
// PunyoGestureFeatures at capture. Kept intentionally small: everything is
// derivable from (x, y, t) triples plus two counters the physics passes in.
//
// Bounded buffer so a very long chase can't grow memory without bound. Old
// samples fall off the front — the tail-end movement is what matters for a
// catch anyway.
//
// Privacy note: samples never leave this recorder. snapshot() reduces them to
// features and the buffer is dropped in the same call.
final class PunyoGestureRecorder {
    private struct Sample {
        let x: CGFloat
        let y: CGFloat
        let t: TimeInterval
    }

    private var samples: [Sample] = []
    private var touchStart: TimeInterval?
    private let capacity = 512

    var isRecording: Bool { touchStart != nil }

    func begin(at point: CGPoint, time: TimeInterval) {
        samples.removeAll(keepingCapacity: true)
        samples.append(Sample(x: point.x, y: point.y, t: time))
        touchStart = time
    }

    func record(at point: CGPoint, time: TimeInterval) {
        guard isRecording else { return }
        // Drop near-duplicate samples so a stationary finger doesn't fill the
        // buffer with zero-length segments that skew mean speed toward 0.
        if let last = samples.last {
            let dx = point.x - last.x
            let dy = point.y - last.y
            if hypot(dx, dy) < 0.5 && (time - last.t) < 0.016 { return }
        }
        samples.append(Sample(x: point.x, y: point.y, t: time))
        if samples.count > capacity {
            samples.removeFirst(samples.count - capacity)
        }
    }

    // Called at capture. Reduces samples to features and drops them.
    func snapshot(
        endTime: TimeInterval,
        grabMissCount: Int,
        deformationPeak: CGFloat,
        radiusMean: CGFloat
    ) -> PunyoGestureFeatures {
        defer { reset() }
        let start = touchStart ?? endTime
        return compute(
            elapsed: max(0, endTime - start),
            grabMissCount: grabMissCount,
            deformationPeak: deformationPeak,
            radiusMean: radiusMean
        )
    }

    func cancel() { reset() }

    private func reset() {
        samples.removeAll(keepingCapacity: true)
        touchStart = nil
    }

    // MARK: - Reduction

    private func compute(
        elapsed: TimeInterval,
        grabMissCount: Int,
        deformationPeak: CGFloat,
        radiusMean: CGFloat
    ) -> PunyoGestureFeatures {
        guard samples.count >= 2 else {
            var f = PunyoGestureFeatures.empty
            f = PunyoGestureFeatures(
                totalDistance: 0, netDisplacement: 0, elapsed: elapsed,
                meanSpeed: 0, peakSpeed: 0, peakAcceleration: 0,
                jitter: 0, curvature: 0, windings: 0, straightness: 1,
                boundingArea: 0,
                grabMissCount: grabMissCount,
                deformationPeak: deformationPeak,
                deformationRatio: radiusMean > 0
                    ? Double(min(1.5, deformationPeak / radiusMean))
                    : 0
            )
            return f
        }

        var totalDistance: CGFloat = 0
        var peakSpeed: CGFloat = 0
        var speeds: [CGFloat] = []
        speeds.reserveCapacity(samples.count - 1)

        var minX = samples[0].x, maxX = samples[0].x
        var minY = samples[0].y, maxY = samples[0].y

        var reversals = 0
        var lastVX: CGFloat = 0
        var lastVY: CGFloat = 0

        var curvatureAccum: Double = 0
        var windingAccum: Double = 0
        var lastAngle: Double? = nil

        for i in 1..<samples.count {
            let a = samples[i - 1]
            let b = samples[i]
            let dt = max(1.0/1000.0, b.t - a.t)
            let dx = b.x - a.x
            let dy = b.y - a.y
            let d = hypot(dx, dy)
            totalDistance += d
            let v = d / CGFloat(dt)
            speeds.append(v)
            if v > peakSpeed { peakSpeed = v }

            // Direction reversal: dot product of consecutive segment vectors
            // is negative. Threshold on segment length keeps noise from
            // triggering it on essentially stationary finger.
            let vx = dx / CGFloat(dt), vy = dy / CGFloat(dt)
            if d > 1.5, (vx * lastVX + vy * lastVY) < 0 { reversals += 1 }
            lastVX = vx
            lastVY = vy

            minX = min(minX, b.x); maxX = max(maxX, b.x)
            minY = min(minY, b.y); maxY = max(maxY, b.y)

            // Angle changes for curvature and winding. Only meaningful when the
            // segment is long enough to have a stable direction.
            if d > 1.5 {
                let ang = atan2(Double(dy), Double(dx))
                if let last = lastAngle {
                    var da = ang - last
                    // Wrap to (-pi, pi] so a single loop counts once.
                    while da > .pi { da -= 2 * .pi }
                    while da < -.pi { da += 2 * .pi }
                    curvatureAccum += abs(da)
                    windingAccum += da
                }
                lastAngle = ang
            }
        }

        let meanSpeed = speeds.isEmpty
            ? 0
            : speeds.reduce(0, +) / CGFloat(speeds.count)

        // Peak acceleration: max |Δspeed| between adjacent speed samples,
        // scaled by their dt. Independent of sign — a hard brake counts.
        var peakAccel: CGFloat = 0
        if speeds.count >= 2 {
            for i in 1..<speeds.count {
                let dt = max(1.0/1000.0, samples[i + 1].t - samples[i].t)
                let a = abs(speeds[i] - speeds[i - 1]) / CGFloat(dt)
                if a > peakAccel { peakAccel = a }
            }
        }

        let start = samples.first!
        let end = samples.last!
        let netDisp = hypot(end.x - start.x, end.y - start.y)
        let straight = totalDistance > 1
            ? Double(min(1.0, netDisp / totalDistance))
            : 1.0

        let jitterNorm = min(1.0, Double(reversals) / max(4.0, Double(samples.count) * 0.25))
        let curvaturePerPx = totalDistance > 1
            ? curvatureAccum / Double(totalDistance)
            : 0
        let windingsWhole = windingAccum / (2 * .pi)
        let area = max(0, (maxX - minX) * (maxY - minY))
        let defRatio = radiusMean > 0
            ? Double(min(1.5, deformationPeak / radiusMean))
            : 0

        return PunyoGestureFeatures(
            totalDistance: totalDistance,
            netDisplacement: netDisp,
            elapsed: elapsed,
            meanSpeed: meanSpeed,
            peakSpeed: peakSpeed,
            peakAcceleration: peakAccel,
            jitter: jitterNorm,
            curvature: curvaturePerPx,
            windings: windingsWhole,
            straightness: straight,
            boundingArea: area,
            grabMissCount: grabMissCount,
            deformationPeak: deformationPeak,
            deformationRatio: defRatio
        )
    }
}
