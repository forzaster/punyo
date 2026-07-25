import SwiftUI

// Full-screen surface that runs the currently selected puni shader as a
// colorEffect on the given background content. All techniques share the same
// argument list — swap the shader function name to swap the visual.
struct PunyoShaderView<Background: View>: View {
    let physics: PunyoPhysics
    let params: PunyoParameters
    let settings: PunyoRenderSettings
    @ViewBuilder let background: () -> Background

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            background()
                .colorEffect(makeShader(time: t))
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
            .float(physics.radius),
            .float(params.viscosity),
            .float(params.elasticity),
        ])
    }
}
