import Foundation

// Stiff and barely deformable, so pressing reads as tapping something solid.
// Full refraction plus low body opacity puts the wallpaper straight through it.
extension PunyoMaterial {
    static let glass = PunyoMaterial(
        id: "glass",
        name: "ガラス",
        physics: PunyoPhysicsPreset(
            viscosity: 0.10,
            elasticity: 520,
            damping: 14.0,
            overshoot: 0.15,
            fleeSpeed: 520,
            fatigue: 0.18,
            curiosity: 0.35
        ),
        appearance: PunyoAppearance(
            baseColor: PunyoRGB(0.85, 0.93, 0.98),
            innerColor: PunyoRGB(0.70, 0.90, 1.00),
            translucency: 0.35,
            refraction: 1.0,
            fresnel: 1.0,
            opacity: 0.55,
            specStrength: 1.20,
            specPower: 96,
            metallic: 0.20,
            grain: 0.0
        )
    )
}
