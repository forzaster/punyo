import Foundation

// Dense and quick. Barely deforms, darts away fast, and hardly ever tires —
// the hardest one to catch. Mirrors the background instead of transmitting it.
extension PunyoMaterial {
    static let mercury = PunyoMaterial(
        id: "mercury",
        name: "水銀",
        physics: PunyoPhysicsPreset(
            viscosity: 0.15,
            elasticity: 380,
            damping: 12.0,
            overshoot: 0.22,
            fleeSpeed: 700,
            fatigue: 0.12,
            curiosity: 0.25
        ),
        appearance: PunyoAppearance(
            baseColor: PunyoRGB(0.76, 0.79, 0.84),
            innerColor: PunyoRGB(0.45, 0.50, 0.58),
            translucency: 0.0,
            refraction: 0.0,
            fresnel: 0.85,
            opacity: 1.0,
            specStrength: 1.40,
            specPower: 92,
            metallic: 0.95,
            grain: 0.0
        )
    )
}
