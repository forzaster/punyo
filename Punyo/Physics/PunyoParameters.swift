import Foundation
import Observation

@Observable
final class PunyoParameters {
    var viscosity: Double = 0.22
    var elasticity: Double = 160.0
    var damping: Double = 6.0
    var overshoot: Double = 0.55
    var fleeSpeed: Double = 420.0

    static let viscosityRange: ClosedRange<Double> = 0.0...1.0
    static let elasticityRange: ClosedRange<Double> = 20.0...600.0
    static let dampingRange: ClosedRange<Double> = 0.5...30.0
    static let overshootRange: ClosedRange<Double> = 0.0...1.0
    static let fleeSpeedRange: ClosedRange<Double> = 0.0...1200.0

    func reset() {
        viscosity = 0.22
        elasticity = 160.0
        damping = 6.0
        overshoot = 0.55
        fleeSpeed = 420.0
    }
}
