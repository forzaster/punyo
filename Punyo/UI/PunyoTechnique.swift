import Foundation
import Observation
import CoreGraphics

enum PunyoEffectKind {
    case colorEffect
    case layerEffect(maxSampleOffset: CGSize)
}

enum PunyoTechnique: String, CaseIterable, Identifiable {
    case sdfBase       = "SDF基本"
    case sdfSSS        = "SSS"
    case sdfSSSRefract = "屈折"

    var id: String { rawValue }

    var shaderName: String {
        switch self {
        case .sdfBase:       return "punyo_sdfBase"
        case .sdfSSS:        return "punyo_sdfSSS"
        case .sdfSSSRefract: return "punyo_sdfSSSRefract"
        }
    }

    var effectKind: PunyoEffectKind {
        switch self {
        case .sdfBase, .sdfSSS:
            return .colorEffect
        case .sdfSSSRefract:
            // Metal side uses up to ~42 px of offset. 64 gives headroom.
            return .layerEffect(maxSampleOffset: CGSize(width: 64, height: 64))
        }
    }
}

@Observable
final class PunyoRenderSettings {
    var technique: PunyoTechnique = .sdfBase
}
