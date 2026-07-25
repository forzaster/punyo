import Foundation
import Observation

@Observable
final class PunyoParameters {
    var viscosity: Double = 0.35
    var elasticity: Double = 180.0
    var damping: Double = 8.0
    var overshoot: Double = 0.35
    var fleeSpeed: Double = 420.0

    static let viscosityRange: ClosedRange<Double> = 0.0...1.0
    static let elasticityRange: ClosedRange<Double> = 20.0...600.0
    static let dampingRange: ClosedRange<Double> = 0.5...30.0
    static let overshootRange: ClosedRange<Double> = 0.0...1.0
    static let fleeSpeedRange: ClosedRange<Double> = 0.0...1200.0

    func reset() {
        viscosity = 0.35
        elasticity = 180.0
        damping = 8.0
        overshoot = 0.35
        fleeSpeed = 420.0
    }
}
