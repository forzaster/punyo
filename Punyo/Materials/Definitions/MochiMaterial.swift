import Foundation

// Slow, sticky, and heavy: high viscosity so it lags behind the finger, low
// stiffness so a press sinks deep, and a long wobble on the way back.
extension PunyoMaterial {
    static let mochi = PunyoMaterial(
        id: "mochi",
        name: "餅",
        physics: PunyoPhysicsPreset(
            viscosity: 0.62,
            elasticity: 130,
            damping: 9.0,
            overshoot: 0.55,
            fleeSpeed: 300,
            fatigue: 0.32,
            curiosity: 0.60,
            squashiness: 0.95
        ),
        appearance: PunyoAppearance(
            baseColor: PunyoRGB(0.97, 0.93, 0.93),
            innerColor: PunyoRGB(1.00, 0.72, 0.75),
            translucency: 0.90,
            refraction: 0.15,
            fresnel: 0.30,
            opacity: 1.0,
            specStrength: 0.35,
            specPower: 22,
            metallic: 0.0,
            grain: 0.04
        )
    )
}
