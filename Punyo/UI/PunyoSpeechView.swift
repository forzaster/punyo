import SwiftUI

// The one line, floating just above the puni. Deliberately not a chat bubble:
// no avatar, no tail, no panel — bare text with a soft shadow so it reads as
// the creature making a noise rather than an app showing a message.
//
// Appearance is computed from elapsed time rather than driven by SwiftUI
// transitions, because this sits inside a TimelineView that redraws every
// frame and implicit animations would fight that.
struct PunyoSpeechView: View {
    let speaker: PunyoSpeaker
    let anchor: CGPoint

    private let popInDuration: TimeInterval = 0.16
    private let fadeOutDuration: TimeInterval = 0.5

    var body: some View {
        if let line = speaker.line {
            let t = speaker.elapsed
            let popIn = min(1.0, t / popInDuration)
            // A little scale overshoot on the way in gives it a "pop" that
            // matches the haptic hit landing at the same instant.
            let bounce = sin(popIn * .pi) * 0.10
            let scale = 0.55 + 0.45 * easeOut(popIn) + bounce

            let fadeStart = speaker.duration - fadeOutDuration
            let fade = t <= fadeStart
                ? 1.0
                : max(0.0, 1.0 - (t - fadeStart) / fadeOutDuration)
            // Drifts upward as it goes, like the sound leaving.
            let rise = -14.0 * (1.0 - fade)

            Text(line)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.6), radius: 5, y: 2)
                .shadow(color: .black.opacity(0.3), radius: 14)
                .scaleEffect(CGFloat(scale))
                .opacity(popIn * fade)
                .position(x: anchor.x, y: anchor.y + CGFloat(rise))
                .allowsHitTesting(false)
        }
    }

    private func easeOut(_ x: Double) -> Double {
        let inv = 1.0 - x
        return 1.0 - inv * inv * inv
    }
}
