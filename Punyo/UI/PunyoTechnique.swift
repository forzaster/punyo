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
    // The bench techniques kept from phase 0, for comparing one effect at a
    // time without a material's numbers in the way.
    case sdfBase       = "SDF基本"
    case sdfSSS        = "SSS"
    case sdfSSSRefract = "屈折"

    var id: String { rawValue }

    var shaderName: String {
        switch self {
        case .toon:          return "punyo_toon"
        case .material:      return "punyo_material"
        case .sdfBase:       return "punyo_sdfBase"
        case .sdfSSS:        return "punyo_sdfSSS"
        case .sdfSSSRefract: return "punyo_sdfSSSRefract"
        }
    }

    // Whether this technique reads the material appearance uniforms. The bench
    // techniques have their own fixed look and take a shorter argument list.
    var usesAppearance: Bool {
        self == .material
    }

    var effectKind: PunyoEffectKind {
        switch self {
        case .material:
            // Refraction reaches 42 px and the metallic mirror sample 54 px.
            // 64 covers both.
            return .layerEffect(maxSampleOffset: CGSize(width: 64, height: 64))
        case .toon, .sdfBase, .sdfSSS:
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
