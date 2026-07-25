import Foundation
import Observation

// The live, tunable physics values. A material writes its preset in here on
// selection; the sliders keep editing the same values afterwards, so picking a
// material is a starting point rather than a lock.
@Observable
final class PunyoParameters {
    var viscosity: Double = 0.22
    var elasticity: Double = 160.0
    var damping: Double = 6.0
    var overshoot: Double = 0.55
    var fleeSpeed: Double = 420.0
    // How fast a chase wears it down (and, at 45% of this rate, how fast it
    // recovers when left alone). 0 = never tires.
    var fatigue: Double = 0.22
    // Pull toward a finger that is keeping its distance.
    var curiosity: Double = 0.5

    static let viscosityRange: ClosedRange<Double> = 0.0...1.0
    static let elasticityRange: ClosedRange<Double> = 20.0...600.0
    static let dampingRange: ClosedRange<Double> = 0.5...30.0
    static let overshootRange: ClosedRange<Double> = 0.0...1.0
    static let fleeSpeedRange: ClosedRange<Double> = 0.0...1200.0
    static let fatigueRange: ClosedRange<Double> = 0.0...1.0
    static let curiosityRange: ClosedRange<Double> = 0.0...1.0

    func apply(_ preset: PunyoPhysicsPreset) {
        viscosity = preset.viscosity
        elasticity = preset.elasticity
        damping = preset.damping
        overshoot = preset.overshoot
        fleeSpeed = preset.fleeSpeed
        fatigue = preset.fatigue
        curiosity = preset.curiosity
    }

    // Reset means "back to this material", not back to some global default —
    // otherwise the button fights whichever material is selected.
    func reset(to preset: PunyoPhysicsPreset) {
        apply(preset)
    }
}
