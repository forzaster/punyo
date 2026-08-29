import SwiftUI

// Full-screen surface that runs the currently selected puni shader on the
// given background content. Techniques that need the background (refraction,
// the material surface) use .layerEffect; opaque bench techniques use
// .colorEffect. Swap the shader function name to swap the visual.
struct PunyoShaderView<Background: View>: View {
    let physics: PunyoPhysics
    let params: PunyoParameters
    let settings: PunyoRenderSettings
    // Lets a state-driven technique swap (♾️ pose) override the user's
    // picked technique for a frame without mutating settings. Defaults to
    // settings.technique so existing call sites don't have to opt in.
    var techniqueOverride: PunyoTechnique? = nil
    @ViewBuilder let background: () -> Background

    private var activeTechnique: PunyoTechnique {
        techniqueOverride ?? settings.technique
    }

    // Shader time must be seconds since this view appeared, not an absolute
    // timestamp: a Shader argument lands in Metal as float32, and an epoch of
    // ~7.9e8 quantizes to steps of ~64 seconds there, which freezes anything
    // driven by sin(time).
    @State private var origin = Date()

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSince(origin)
            let shader = makeShader(time: t)
            switch activeTechnique.effectKind {
            case .colorEffect:
                background().colorEffect(shader)
            case .layerEffect(let offset):
                background().layerEffect(shader, maxSampleOffset: offset)
            }
        }
    }

    private func makeShader(time: TimeInterval) -> Shader {
        let function = ShaderFunction(library: .default,
                                      name: activeTechnique.shaderName)

        if activeTechnique.usesInfinityPose {
            return infinityShader(function: function, time: time)
        }

        var arguments = geometryPrefix(time: time)

        if activeTechnique.usesAppearance {
            arguments.append(.float(physics.stamina))
            arguments.append(.float2(physics.velocity))
            arguments.append(contentsOf: settings.material.appearance.shaderArguments)
        } else {
            arguments.append(.float(params.viscosity))
            arguments.append(.float(params.elasticity))
        }

        return Shader(function: function, arguments: arguments)
    }

    // The geometry block every stitchable entry point takes, in order, right
    // after the implicit position and colour/layer parameters. Built in one
    // place on purpose: a technique that assembles its own prefix is how the
    // order drifts, and a single misplaced float silently reinterprets every
    // argument after it rather than failing to compile.
    //
    // Order must match the Metal signatures exactly:
    //   float4 boundingRect, float time, float2 fingerPos, float fingerActive,
    //   float2 center, float2 deformation, float2 axes, float squash
    private func geometryPrefix(time: TimeInterval) -> [Shader.Argument] {
        [
            .boundingRect,
            .float(time),
            .float2(physics.fingerPosition),
            .float(physics.isFingerDown ? 1.0 : 0.0),
            .float2(physics.center),
            .float2(CGVector(dx: physics.deformation.dx,
                             dy: physics.deformation.dy)),
            .float2(CGSize(width: physics.radiusX, height: physics.radiusY)),
            // Scalar squash sits with the geometry block, ahead of anything
            // per-technique: every entry point takes the same shared prefix.
            .float(physics.squash),
        ]
    }

    // Metaball marshaller — separate function because the tail of the argument
    // list is a different shape (lobe positions + radii instead of the
    // appearance block's stamina/velocity) and mixing that into the primary
    // path clutters the read. The geometry prefix is still the shared one.
    private func infinityShader(function: ShaderFunction,
                                time: TimeInterval) -> Shader {
        let (a, b) = physics.infinityLobeCenters(params: params)
        let r = physics.infinityLobeRadius(params: params)
        // The base ♾️ is two lobes. A future 3rd small pinch lobe or a chain
        // of extra lobes can be added by extending this array — the shader
        // is already sized for four.
        let lobes: [CGPoint] = [a, b]
        let radii: [CGFloat] = [r, r]

        var arguments = geometryPrefix(time: time)
        arguments.append(contentsOf: [
            .float(physics.stamina),
            // Lobe positions padded out to the shader's fixed capacity of 4.
            // Trailing slots have radius 0 (see radiiArg) so the shader skips
            // them cheaply.
            .float2(pointOrZero(lobes, 0)),
            .float2(pointOrZero(lobes, 1)),
            .float2(pointOrZero(lobes, 2)),
            .float2(pointOrZero(lobes, 3)),
            .float4(radiusOrZero(radii, 0), radiusOrZero(radii, 1),
                    radiusOrZero(radii, 2), radiusOrZero(radii, 3)),
            .float(Float(lobes.count)),
            .float(Float(params.infinityThreshold)),
        ])
        arguments.append(contentsOf: settings.material.appearance.shaderArguments)
        return Shader(function: function, arguments: arguments)
    }

    private func pointOrZero(_ points: [CGPoint], _ index: Int) -> CGPoint {
        index < points.count ? points[index] : .zero
    }

    private func radiusOrZero(_ radii: [CGFloat], _ index: Int) -> CGFloat {
        index < radii.count ? radii[index] : 0
    }
}

private extension PunyoAppearance {
    // Packed into two float4s and a trailing pair so the ordering stays
    // checkable against the Metal signature at a glance.
    //
    // Order must match the tail of every usesAppearance signature exactly:
    //   float3 baseColor, float3 innerColor, float4 optics, float4 surface,
    //   float2 film
    var shaderArguments: [Shader.Argument] {
        [
            .float3(CGFloat(baseColor.r), CGFloat(baseColor.g), CGFloat(baseColor.b)),
            .float3(CGFloat(innerColor.r), CGFloat(innerColor.g), CGFloat(innerColor.b)),
            .float4(CGFloat(translucency), CGFloat(refraction),
                    CGFloat(fresnel), CGFloat(opacity)),
            .float4(CGFloat(specStrength), CGFloat(specPower),
                    CGFloat(metallic), CGFloat(grain)),
            // The film pair is deliberately not padded out to a float4: two
            // dead lanes are an invitation for the next effect to squat in
            // them, and appending a fresh argument is cheaper to review than
            // decoding what .z of a half-used vector means today. Every
            // usesAppearance entry point has to declare this trailing float2 —
            // one that doesn't will silently reinterpret nothing, because it
            // is last, but the block would drift the moment anything is added
            // after it.
            .float2(CGFloat(iridescence), CGFloat(filmThickness)),
        ]
    }
}
