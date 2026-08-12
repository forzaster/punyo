import Foundation

// A material is the pair of things that make a puni feel like a substance: how
// it moves (a physics preset) and how it looks (appearance uniforms).
//
// Adding one is meant to cost a single file: define a `static let` in an
// extension of PunyoMaterial with numbers only, then list it in
// PunyoMaterialLibrary.all. No new Metal function, no new Swift type — the
// material shader is appearance-driven precisely so that stays true.
struct PunyoMaterial: Identifiable {
    let id: String
    let name: String
    let physics: PunyoPhysicsPreset
    let appearance: PunyoAppearance
}

struct PunyoRGB {
    var r: Double
    var g: Double
    var b: Double

    init(_ r: Double, _ g: Double, _ b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }
}

// The five phase 0 knobs plus the two phase 2 ones. Selecting a material writes
// these into the live PunyoParameters, and the sliders keep working from there —
// a material is a starting point to tune from, not a lock.
struct PunyoPhysicsPreset {
    var viscosity: Double
    var elasticity: Double
    var damping: Double
    var overshoot: Double
    var fleeSpeed: Double
    var fatigue: Double
    var curiosity: Double
    // How far a press flattens the body. The scalar deformation channel, so it
    // is what separates something you can squash flat from something that just
    // sits there when you push on it.
    var squashiness: Double
}

// What gets handed to the material shader. Every field is a weight on an effect
// that is always compiled in, so a material is expressed purely as numbers.
struct PunyoAppearance {
    // Surface colour.
    var baseColor: PunyoRGB
    // Colour of light that has travelled through the body (pseudo SSS).
    var innerColor: PunyoRGB
    // 0 = opaque solid, 1 = light pours through it. Mochi, jelly, smoke.
    var translucency: Double
    // 0 = no bending of the background, 1 = full screen-space refraction.
    var refraction: Double
    // Rim brightness. High for anything wet or glassy.
    var fresnel: Double
    // Whole-body opacity. Below 1 the background shows through everywhere,
    // which is what makes smoke and glass sit *in* the scene.
    var opacity: Double
    var specStrength: Double
    // Highlight tightness. Low is broad and matte, high is a hard glint.
    var specPower: Double
    // Treats the background as an environment to mirror. Drives the metals.
    var metallic: Double
    // Procedural noise: roughens the normal, speckles the colour, and frays the
    // rim so grainy things don't read as a hard-edged ball.
    var grain: Double
}
