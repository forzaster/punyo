import Foundation
import Observation
import CoreGraphics

enum PunyoEffectKind {
    case colorEffect
    case layerEffect(maxSampleOffset: CGSize)
}

enum PunyoTechnique: String, CaseIterable, Identifiable {
    case toon          = "Toon"
    // The appearance-driven surface every material runs through.
    case material      = "素材"
    // Toon shading applied to the selected material's colors. Same appearance
    // uniforms as `.material`; different visual style.
    case toonMaterial  = "Toon素材"
    // The bench techniques kept from phase 0, for comparing one effect at a
    // time without a material's numbers in the way.
    case sdfBase       = "SDF基本"
    case sdfSSS        = "SSS"
    case sdfSSSRefract = "屈折"
    // ♾️ pose. Not in the picker — the render layer swaps to this when the
    // pose is engaged and swaps back on collapse, so it stays a state-driven
    // effect rather than a top-level mode the user has to remember to set.
    case infinityMaterial = "♾️"

    var id: String { rawValue }

    var shaderName: String {
        switch self {
        case .toon:              return "punyo_toon"
        case .material:          return "punyo_material"
        case .toonMaterial:      return "punyo_toonMaterial"
        case .sdfBase:           return "punyo_sdfBase"
        case .sdfSSS:            return "punyo_sdfSSS"
        case .sdfSSSRefract:     return "punyo_sdfSSSRefract"
        case .infinityMaterial:  return "punyo_infinityMaterial"
        }
    }

    // Whether this technique reads the material appearance uniforms. The bench
    // techniques have their own fixed look and take a shorter argument list.
    var usesAppearance: Bool {
        self == .material || self == .toonMaterial || self == .infinityMaterial
    }

    // Whether the technique consumes the ♾️ pose uniforms in place of the
    // ellipse `axes` + `deformation` uniforms. Keeps the marshaller table-
    // driven instead of switching on the case in ContentView.
    var usesInfinityPose: Bool {
        self == .infinityMaterial
    }

    // Whether the technique should appear in the debug picker. Pose-driven
    // techniques are toggled by state, not selected by hand.
    var isPickable: Bool {
        self != .infinityMaterial
    }

    var effectKind: PunyoEffectKind {
        switch self {
        case .material, .infinityMaterial:
            // Refraction reaches 42 px and the metallic mirror sample 54 px.
            // 64 covers both. The metaball shader only samples at (position),
            // but declaring the wider offset here means switching to it does
            // not force a pipeline reconfiguration.
            return .layerEffect(maxSampleOffset: CGSize(width: 64, height: 64))
        case .toon, .toonMaterial, .sdfBase, .sdfSSS:
            return .colorEffect
        case .sdfSSSRefract:
            return .layerEffect(maxSampleOffset: CGSize(width: 64, height: 64))
        }
    }
}

@Observable
final class PunyoRenderSettings {
    var technique: PunyoTechnique = .material
    var material: PunyoMaterial = PunyoMaterialLibrary.starting
}
