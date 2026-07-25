import Foundation
import Observation

enum PunyoTechnique: String, CaseIterable, Identifiable {
    case sdfBase = "SDF基本"

    var id: String { rawValue }

    var shaderName: String {
        switch self {
        case .sdfBase: return "punyo_sdfBase"
        }
    }
}

@Observable
final class PunyoRenderSettings {
    var technique: PunyoTechnique = .sdfBase
}
