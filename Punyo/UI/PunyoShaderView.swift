import SwiftUI

// Full-screen surface that runs the currently selected puni shader on the
// given background content. Techniques that need the background (refraction)
// use .layerEffect; opaque techniques use .colorEffect. Swap the shader
// function name to swap the visual.
struct PunyoShaderView<Background: View>: View {
    let physics: PunyoPhysics
    let params: PunyoParameters
    let settings: PunyoRenderSettings
    @ViewBuilder let background: () -> Background

    // Shader time must be seconds since this view appeared, not an absolute
    // timestamp: a Shader argument lands in Metal as float32, and an epoch of
    // ~7.9e8 quantizes to steps of ~64 seconds there, which freezes anything
    // driven by sin(time).
    @State private var origin = Date()

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSince(origin)
            let shader = makeShader(time: t)
            switch settings.technique.effectKind {
            case .colorEffect:
                background().colorEffect(shader)
            case .layerEffect(let offset):
                background().layerEffect(shader, maxSampleOffset: offset)
            }
        }
    }

    private func makeShader(time: TimeInterval) -> Shader {
        let function = ShaderFunction(library: .default,
                                      name: settings.technique.shaderName)
        return Shader(function: function, arguments: [
            .boundingRect,
            .float(time),
            .float2(physics.fingerPosition),
            .float(physics.isFingerDown ? 1.0 : 0.0),
            .float2(physics.center),
            .float2(CGVector(dx: physics.deformation.dx,
                             dy: physics.deformation.dy)),
            .float2(CGSize(width: physics.radiusX, height: physics.radiusY)),
            .float(params.viscosity),
            .float(params.elasticity),
            .float(physics.stamina),
            .float2(physics.velocity),
        ])
    }
}
