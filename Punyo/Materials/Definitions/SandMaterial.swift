import Foundation

// Slumps rather than bounces: very viscous, weak spring, heavy damping, almost
// no overshoot. Tires fast, so it is the forgiving one to catch.
extension PunyoMaterial {
    static let sand = PunyoMaterial(
        id: "sand",
        name: "砂",
        physics: PunyoPhysicsPreset(
            viscosity: 0.85,
            elasticity: 90,
            damping: 16.0,
            overshoot: 0.05,
            fleeSpeed: 240,
            fatigue: 0.50,
            curiosity: 0.40,
            squashiness: 0.55
        ),
        appearance: PunyoAppearance(
            baseColor: PunyoRGB(0.86, 0.72, 0.45),
            innerColor: PunyoRGB(0.60, 0.45, 0.25),
            translucency: 0.05,
            refraction: 0.0,
            fresnel: 0.15,
            opacity: 1.0,
            specStrength: 0.15,
            specPower: 10,
            metallic: 0.0,
            grain: 1.0
        )
    )
}
