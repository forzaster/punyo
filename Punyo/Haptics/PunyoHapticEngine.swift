import Foundation
import CoreHaptics

// Continuous-haptics driver for the puni. `begin` starts a long-running
// continuous event; `update` retunes its intensity/sharpness each frame via
// dynamic parameters (no re-planning cost); `end` stops it. `transientTap`
// is a one-shot used later by capture-style feedback.
//
// Silently no-ops on devices without haptics support (simulator, Preview) so
// the rest of the app can call it unconditionally.
final class PunyoHapticEngine {
    private let supported: Bool
    private var engine: CHHapticEngine?
    private var player: CHHapticAdvancedPatternPlayer?

    init() {
        supported = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    }

    // MARK: - Lifecycle

    // Lazy engine creation. Safe to call repeatedly.
    private func ensureEngine() -> CHHapticEngine? {
        guard supported else { return nil }
        if let engine { return engine }
        do {
            let e = try CHHapticEngine()
            e.playsHapticsOnly = true
            e.stoppedHandler = { [weak self] _ in
                self?.player = nil
            }
            e.resetHandler = { [weak self] in
                self?.player = nil
                try? self?.engine?.start()
            }
            try e.start()
            engine = e
            return e
        } catch {
            engine = nil
            return nil
        }
    }

    // MARK: - Continuous

    func begin(intensity: Float, sharpness: Float) {
        guard let engine = ensureEngine() else { return }
        // Stop any prior continuous stream before starting a fresh one.
        if let old = player {
            try? old.stop(atTime: CHHapticTimeImmediate)
            player = nil
        }
        let event = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: clamp01(intensity)),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: clamp01(sharpness)),
            ],
            relativeTime: 0,
            // Long enough to outlast any touch; we stop it explicitly on release.
            duration: 30.0
        )
        do {
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let p = try engine.makeAdvancedPlayer(with: pattern)
            p.loopEnabled = false
            try p.start(atTime: CHHapticTimeImmediate)
            player = p
        } catch {
            player = nil
        }
    }

    func update(intensity: Float, sharpness: Float) {
        guard let player else { return }
        do {
            try player.sendParameters([
                CHHapticDynamicParameter(parameterID: .hapticIntensityControl,
                                         value: clamp01(intensity),
                                         relativeTime: 0),
                CHHapticDynamicParameter(parameterID: .hapticSharpnessControl,
                                         value: clamp01(sharpness),
                                         relativeTime: 0),
            ], atTime: CHHapticTimeImmediate)
        } catch {
            // Engine may have been reset mid-touch; drop the player so a
            // subsequent begin() rebuilds cleanly.
            self.player = nil
        }
    }

    func end() {
        guard let player else { return }
        try? player.stop(atTime: CHHapticTimeImmediate)
        self.player = nil
    }

    // MARK: - Transient (reserved for future capture feedback)

    func transientTap(intensity: Float, sharpness: Float) {
        guard let engine = ensureEngine() else { return }
        let event = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: clamp01(intensity)),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: clamp01(sharpness)),
            ],
            relativeTime: 0
        )
        do {
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let p = try engine.makePlayer(with: pattern)
            try p.start(atTime: CHHapticTimeImmediate)
        } catch {}
    }

    private func clamp01(_ v: Float) -> Float { max(0, min(1, v)) }
}
