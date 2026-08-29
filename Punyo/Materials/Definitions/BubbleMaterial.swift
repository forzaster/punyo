import Foundation

// Almost nothing there: the weakest spring of any material, barely damped, and
// the largest overshoot, so a press sends it wobbling for a long time and it
// never quite settles. Tires fast and is easily curious — it drifts over to be
// touched and then can hardly take being touched.
//
// The look is carried by the film rather than by the body. Opacity is low
// enough that the wallpaper reads straight through the middle, which leaves
// the rim doing all the work: very high fresnel for the bright outline, and
// the iridescence on top of that for the rainbow banding that makes it a soap
// bubble instead of a pale grey ball. Thickness sits at 340nm, in the range
// where the first-order bands are the saturated magenta-to-cyan ones rather
// than the washed-out higher orders.
extension PunyoMaterial {
    static let bubble = PunyoMaterial(
        id: "bubble",
        name: "シャボン玉",
        physics: PunyoPhysicsPreset(
            viscosity: 0.88,
            elasticity: 55,
            damping: 3.5,
            overshoot: 0.92,
            fleeSpeed: 420,
            fatigue: 0.45,
            curiosity: 0.75,
            squashiness: 1.0
        ),
        appearance: PunyoAppearance(
            baseColor: PunyoRGB(0.88, 0.94, 1.00),
            innerColor: PunyoRGB(0.78, 0.90, 1.00),
            translucency: 1.0,
            refraction: 0.85,
            fresnel: 1.40,
            opacity: 0.40,
            specStrength: 1.10,
            specPower: 110,
            metallic: 0.0,
            grain: 0.0,
            iridescence: 0.90,
            filmThickness: 340
        )
    )
}
