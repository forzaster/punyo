import Foundation

// Barely there: almost no spring, light damping and huge overshoot so it drifts
// and keeps drifting. Never really tires and always comes back, which makes it
// the one that is hard to catch but impossible to get rid of.
extension PunyoMaterial {
    static let smoke = PunyoMaterial(
        id: "smoke",
        name: "煙",
        physics: PunyoPhysicsPreset(
            viscosity: 0.95,
            elasticity: 60,
            damping: 5.0,
            overshoot: 0.80,
            fleeSpeed: 380,
            fatigue: 0.08,
            curiosity: 0.80
        ),
        appearance: PunyoAppearance(
            baseColor: PunyoRGB(0.62, 0.64, 0.72),
            innerColor: PunyoRGB(0.85, 0.86, 0.95),
            translucency: 1.0,
            refraction: 0.50,
            fresnel: 0.25,
            opacity: 0.35,
            specStrength: 0.10,
            specPower: 12,
            metallic: 0.0,
            grain: 0.70
        )
    )
}
