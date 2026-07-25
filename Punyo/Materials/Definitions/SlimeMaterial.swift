import Foundation

// The baseline: bouncy, wet, translucent. Everything else is a departure from
// this one.
extension PunyoMaterial {
    static let slime = PunyoMaterial(
        id: "slime",
        name: "スライム",
        physics: PunyoPhysicsPreset(
            viscosity: 0.30,
            elasticity: 200,
            damping: 7.0,
            overshoot: 0.45,
            fleeSpeed: 460,
            fatigue: 0.22,
            curiosity: 0.50
        ),
        appearance: PunyoAppearance(
            baseColor: PunyoRGB(0.46, 0.86, 0.52),
            innerColor: PunyoRGB(0.82, 1.00, 0.45),
            translucency: 0.75,
            refraction: 0.35,
            fresnel: 0.55,
            opacity: 1.0,
            specStrength: 0.70,
            specPower: 48,
            metallic: 0.0,
            grain: 0.0
        )
    )
}
