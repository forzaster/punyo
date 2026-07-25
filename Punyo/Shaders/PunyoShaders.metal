#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// --- Shared helpers ---------------------------------------------------------
//
// The puni is an ellipse with axes = (rx, ry). We compute a normalized
// coordinate `relN = (p - center) / axes`; the base ellipse boundary is then
// `|relN| == 1`. Deformation adds an angular bulge in this normalized space,
// and the SDF is scaled by min(axes) back into approximate point space.

static inline float sdPunyoSilhouette(float2 p,
                                      float2 center,
                                      float2 axes,
                                      float2 deformation) {
    float2 rel = p - center;
    float2 relN = rel / axes;
    float dN = length(relN);
    float sdScale = min(axes.x, axes.y);
    float dmag = length(deformation);
    float bulgeN = 0.0;
    if (dmag > 0.0001) {
        float2 dn = deformation / dmag;
        float2 relDir = relN / max(dN, 0.0001);
        float cosang = dot(relDir, dn);
        bulgeN = (dmag / sdScale) * cosang * 0.55;
    }
    return (dN - (1.0 + bulgeN)) * sdScale;
}

static inline float insideHeight(float2 p,
                                 float2 center,
                                 float2 axes,
                                 float2 deformation) {
    float sdScale = min(axes.x, axes.y);
    float sd = sdPunyoSilhouette(p, center, axes, deformation);
    float inside = max(0.0, -sd);
    // Dome height as if the local slice were a hemisphere of radius sdScale.
    // This gives a pseudo-3D bump even on an ellipsoidal silhouette.
    return sqrt(max(0.0, sdScale * sdScale - (sdScale - inside) * (sdScale - inside)));
}

static inline float3 punyoNormal(float2 p,
                                 float2 center,
                                 float2 axes,
                                 float2 deformation) {
    const float eps = 1.5;
    float hxP = insideHeight(p + float2(eps, 0.0), center, axes, deformation);
    float hxN = insideHeight(p - float2(eps, 0.0), center, axes, deformation);
    float hyP = insideHeight(p + float2(0.0, eps), center, axes, deformation);
    float hyN = insideHeight(p - float2(0.0, eps), center, axes, deformation);
    float3 grad = float3((hxP - hxN) / (2.0 * eps),
                         (hyP - hyN) / (2.0 * eps),
                         1.0);
    return normalize(float3(-grad.x, -grad.y, grad.z));
}

static inline float punyoCoverage(float sd) {
    const float aa = 1.0;
    return smoothstep(aa, -aa, sd);
}

static inline float3 punyoFatigueTint(float3 base, float tired) {
    float luma = dot(base, float3(0.299, 0.587, 0.114));
    return mix(base, float3(luma), tired * 0.45) * (1.0 - tired * 0.18);
}

// --- Technique 0: Toon shader (default) -------------------------------------
// Quantized diffuse into 3 bands, a hard specular hotspot, a dark ink outline
// at the silhouette edge, and a soft "cheek" blush. Reads as a sticker /
// mascot rendering.

[[ stitchable ]] half4 punyo_toon(
    float2 position,
    half4 currentColor,
    float4 boundingRect,
    float time,
    float2 fingerPos,
    float fingerActive,
    float2 center,
    float2 deformation,
    float2 axes,
    float viscosity,
    float elasticity
) {
    float sd = sdPunyoSilhouette(position, center, axes, deformation);
    float coverage = punyoCoverage(sd);
    if (coverage < 0.001) {
        return currentColor;
    }

    float3 n = punyoNormal(position, center, axes, deformation);
    float3 L = normalize(float3(-0.35, -0.55, 0.75));
    float3 V = float3(0.0, 0.0, 1.0);
    float3 H = normalize(L + V);
    float diff = dot(n, L);
    float spec = pow(max(0.0, dot(n, H)), 40.0);

    // Quantize diffuse into three lit + one shadow band. Smooth the thresholds
    // slightly so the bands don't look aliased on curved surfaces.
    float d1 = smoothstep(0.10, 0.15, diff);
    float d2 = smoothstep(0.42, 0.48, diff);
    float d3 = smoothstep(0.78, 0.83, diff);
    float toonDiff = 0.35 + 0.20 * d1 + 0.25 * d2 + 0.20 * d3;

    float3 base   = float3(0.98, 0.55, 0.82);
    float3 shadow = float3(0.62, 0.28, 0.55);
    float3 body   = mix(shadow, base, toonDiff);

    // Ink outline: darken pixels within a ring of the silhouette.
    float outline = 1.0 - smoothstep(1.5, 4.0, -sd);
    body *= mix(1.0, 0.35, outline);

    // Hard specular hotspot.
    float toonSpec = smoothstep(0.55, 0.62, spec);
    body += float3(1.0, 0.98, 1.0) * toonSpec * 0.85;

    // Blush: two soft spots offset toward the top of the dome.
    float2 blushDir1 = float2(-0.35, -0.15);
    float2 blushDir2 = float2( 0.35, -0.15);
    float2 relN = (position - center) / axes;
    float b1 = smoothstep(0.32, 0.08, length(relN - blushDir1));
    float b2 = smoothstep(0.32, 0.08, length(relN - blushDir2));
    body = mix(body, body * float3(1.15, 0.75, 0.85), min(1.0, (b1 + b2) * 0.55));

    half3 outCol = mix(currentColor.rgb, half3(body), half(coverage));
    return half4(outCol, max(currentColor.a, half(coverage)));
}

// --- Procedural noise -------------------------------------------------------
// Value noise + 3 octaves of FBM. Drives the grainy materials: roughens the
// normal, speckles the colour, and frays the rim.

static inline float punyoHash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

static inline float punyoValueNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    float a = punyoHash(i);
    float b = punyoHash(i + float2(1.0, 0.0));
    float c = punyoHash(i + float2(0.0, 1.0));
    float d = punyoHash(i + float2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

static inline float punyoFBM(float2 p) {
    float sum = 0.0;
    float amp = 0.5;
    for (int i = 0; i < 3; ++i) {
        sum += amp * punyoValueNoise(p);
        p *= 2.03;
        amp *= 0.5;
    }
    return sum;
}

// --- Material surface -------------------------------------------------------
// One appearance-driven surface that every phase 4 material runs through. Each
// effect is always compiled in and weighted by a uniform, which is what keeps
// "add a material" down to a Swift file of numbers instead of a new shader.
//
//   optics  = (translucency, refraction, fresnel, opacity)
//   surface = (specStrength, specPower, metallic, grain)

[[ stitchable ]] half4 punyo_material(
    float2 position,
    SwiftUI::Layer layer,
    float4 boundingRect,
    float time,
    float2 fingerPos,
    float fingerActive,
    float2 center,
    float2 deformation,
    float2 axes,
    float stamina,
    float2 velocity,
    float3 baseColor,
    float3 innerColor,
    float4 optics,
    float4 surface
) {
    float tired = clamp(1.0 - stamina, 0.0, 1.0);
    float sdScale = min(axes.x, axes.y);
    float sd = sdPunyoSilhouette(position, center, axes, deformation);
    float coverage = punyoCoverage(sd);
    if (coverage < 0.001) {
        return layer.sample(position);
    }

    float translucency = optics.x;
    float refraction   = optics.y;
    float fresnelAmt   = optics.z;
    float bodyOpacity  = optics.w;
    float specStrength = surface.x;
    float specPower    = surface.y;
    float metallic     = surface.z;
    float grain        = surface.w;

    float3 n = punyoNormal(position, center, axes, deformation);
    float inside = max(0.0, -sd);
    float thickness = clamp(inside / max(sdScale, 0.001), 0.0, 1.0);

    if (grain > 0.001) {
        // Roughen the normal from the noise gradient.
        float2 gp = (position - center) * 0.25;
        float nx = punyoFBM(gp + float2(1.7, 0.0)) - punyoFBM(gp - float2(1.7, 0.0));
        float ny = punyoFBM(gp + float2(0.0, 1.7)) - punyoFBM(gp - float2(0.0, 1.7));
        n = normalize(n + float3(nx, ny, 0.0) * grain * 0.9);

        // Fray the rim only, so sand crumbles and smoke dissolves at the edge
        // while the core stays solid.
        float edge = 1.0 - thickness;
        float2 fp = (position - center) * 0.08 + float2(time * 0.06, 0.0);
        float fray = punyoFBM(fp);
        coverage *= clamp(1.0 - grain * edge * edge * (0.9 - fray), 0.0, 1.0);
    }

    float3 L = normalize(float3(-0.4, -0.55, 0.75));
    float3 V = float3(0.0, 0.0, 1.0);
    float3 H = normalize(L + V);

    const float wrap = 0.3;
    float diff = max(0.0, (dot(n, L) + wrap) / (1.0 + wrap));
    float spec = pow(max(0.0, dot(n, H)), max(1.0, specPower))
               * specStrength * (1.0 - tired * 0.5);
    float fresnel = pow(1.0 - max(0.0, n.z), 3.0) * fresnelAmt;

    float3 base = punyoFatigueTint(baseColor, tired);

    // Pseudo SSS: light that entered the back and came out toward the camera.
    float backFacing = max(0.0, dot(-n, L));
    float transmission = pow(1.0 - thickness, 2.5);
    float3 sss = punyoFatigueTint(innerColor, tired)
               * (backFacing * transmission * translucency * 1.6);

    float3 col = base * (0.30 + 0.70 * diff) + sss;

    // Screen-space refraction: the background bent by the body.
    if (refraction > 0.001) {
        const float maxRefract = 42.0;
        float2 off = -n.xy * (maxRefract * refraction * thickness);
        float2 sp = clamp(position + off, float2(0.0), boundingRect.zw);
        float3 seen = float3(layer.sample(sp).rgb) * float3(1.02, 0.96, 1.0);
        // Rim stays surface, core lets things through.
        float pass = mix(0.60, 0.05, fresnel) * refraction;
        col = mix(col, seen, pass);
    }

    // Environment-ish reflection: sample the background wide of the normal and
    // treat it as what a mirrored surface is picking up.
    if (metallic > 0.001) {
        const float mirrorSpread = 54.0;
        float2 off = n.xy * mirrorSpread;
        float2 sp = clamp(position + off, float2(0.0), boundingRect.zw);
        float3 env = float3(layer.sample(sp).rgb) * 1.4 + float3(0.10);
        col = mix(col, env * base, metallic);
    }

    col += float3(1.0, 0.94, 0.97) * spec;
    col += base * fresnel * 0.55;

    if (grain > 0.001) {
        float speck = punyoFBM((position - center) * 0.9) - 0.5;
        col *= 1.0 + speck * grain * 0.45;
    }

    // Contact shadow just outside the silhouette.
    float shadow = smoothstep(sdScale * 0.55, 0.0, sd) * (1.0 - coverage);
    float3 bg = float3(layer.sample(position).rgb) * (1.0 - shadow * 0.35);

    // Body opacity is what lets smoke and glass sit *in* the scene rather than
    // on top of it.
    float bodyAlpha = coverage * bodyOpacity;
    float3 outCol = mix(bg, col, bodyAlpha);
    return half4(half3(outCol), 1.0);
}

// --- Technique 1: SDF base (dome, Lambert + Blinn-Phong) --------------------

[[ stitchable ]] half4 punyo_sdfBase(
    float2 position,
    half4 currentColor,
    float4 boundingRect,
    float time,
    float2 fingerPos,
    float fingerActive,
    float2 center,
    float2 deformation,
    float2 axes,
    float viscosity,
    float elasticity
) {
    float sd = sdPunyoSilhouette(position, center, axes, deformation);
    float coverage = punyoCoverage(sd);
    if (coverage < 0.001) {
        return currentColor;
    }

    float3 n = punyoNormal(position, center, axes, deformation);
    float3 L = normalize(float3(-0.4, -0.55, 0.75));
    float3 V = float3(0.0, 0.0, 1.0);
    float3 H = normalize(L + V);
    float diff = max(0.0, dot(n, L));
    float spec = pow(max(0.0, dot(n, H)), 48.0);
    float rim  = pow(1.0 - max(0.0, n.z), 3.0);

    float3 base = float3(0.86, 0.44, 0.78);
    float3 col  = base * (0.35 + 0.75 * diff)
                + float3(1.0, 0.85, 0.95) * spec * 0.7
                + float3(1.0, 0.7, 0.9) * rim * 0.35;

    float sdScale = min(axes.x, axes.y);
    float shadow = smoothstep(sdScale * 0.55, 0.0, sd) * (1.0 - coverage);
    half3 bg = currentColor.rgb * half(1.0 - shadow * 0.35);

    half3 outCol = mix(bg, half3(col), half(coverage));
    return half4(outCol, max(currentColor.a, half(coverage)));
}

// --- Technique 2: SDF + pseudo SSS -----------------------------------------

[[ stitchable ]] half4 punyo_sdfSSS(
    float2 position,
    half4 currentColor,
    float4 boundingRect,
    float time,
    float2 fingerPos,
    float fingerActive,
    float2 center,
    float2 deformation,
    float2 axes,
    float viscosity,
    float elasticity
) {
    float sd = sdPunyoSilhouette(position, center, axes, deformation);
    float coverage = punyoCoverage(sd);
    if (coverage < 0.001) {
        return currentColor;
    }

    float3 n = punyoNormal(position, center, axes, deformation);
    float sdScale = min(axes.x, axes.y);
    float3 L = normalize(float3(-0.4, -0.55, 0.75));
    float3 V = float3(0.0, 0.0, 1.0);
    float3 H = normalize(L + V);
    const float wrap = 0.3;
    float diff = max(0.0, (dot(n, L) + wrap) / (1.0 + wrap));
    float spec = pow(max(0.0, dot(n, H)), 42.0);

    float inside = max(0.0, -sd);
    float thickness = clamp(inside / max(sdScale, 0.001), 0.0, 1.0);
    float backFacing = max(0.0, dot(-n, L));
    float transmission = pow(1.0 - thickness, 2.5);
    float sssGlow = backFacing * transmission;

    float3 base    = float3(0.86, 0.44, 0.78);
    float3 inner   = float3(1.00, 0.55, 0.65);
    float3 rimCol  = float3(1.00, 0.75, 0.85);

    float3 surface = base * (0.30 + 0.70 * diff);
    float3 sss     = inner * sssGlow * 1.4;
    float rim      = pow(1.0 - max(0.0, n.z), 2.6);
    float3 col     = surface + sss + rimCol * rim * 0.35 + float3(1.0, 0.9, 0.95) * spec * 0.55;

    float shadow = smoothstep(sdScale * 0.55, 0.0, sd) * (1.0 - coverage);
    half3 bg = currentColor.rgb * half(1.0 - shadow * 0.35);

    half3 outCol = mix(bg, half3(col), half(coverage));
    return half4(outCol, max(currentColor.a, half(coverage)));
}

// --- Technique 3: SDF + SSS + screen-space refraction ----------------------

[[ stitchable ]] half4 punyo_sdfSSSRefract(
    float2 position,
    SwiftUI::Layer layer,
    float4 boundingRect,
    float time,
    float2 fingerPos,
    float fingerActive,
    float2 center,
    float2 deformation,
    float2 axes,
    float viscosity,
    float elasticity
) {
    float sd = sdPunyoSilhouette(position, center, axes, deformation);
    float coverage = punyoCoverage(sd);
    if (coverage < 0.001) {
        return layer.sample(position);
    }

    float3 n = punyoNormal(position, center, axes, deformation);
    float sdScale = min(axes.x, axes.y);
    float inside = max(0.0, -sd);
    float thickness = clamp(inside / max(sdScale, 0.001), 0.0, 1.0);

    const float refractPixels = 42.0;
    float2 refractOffset = -n.xy * (refractPixels * thickness);
    float2 samplePos = clamp(position + refractOffset,
                             float2(0.0, 0.0),
                             boundingRect.zw);
    half4 refracted = layer.sample(samplePos);

    float3 L = normalize(float3(-0.4, -0.55, 0.75));
    float3 V = float3(0.0, 0.0, 1.0);
    float3 H = normalize(L + V);
    const float wrap = 0.3;
    float diff = max(0.0, (dot(n, L) + wrap) / (1.0 + wrap));
    float spec = pow(max(0.0, dot(n, H)), 44.0);
    float backFacing = max(0.0, dot(-n, L));
    float transmission = pow(1.0 - thickness, 2.5);
    float sssGlow = backFacing * transmission;

    float3 base  = float3(0.86, 0.44, 0.78);
    float3 inner = float3(1.00, 0.55, 0.65);
    float3 surface = base * (0.30 + 0.70 * diff) + inner * sssGlow * 1.4;

    float fresnel = pow(1.0 - max(0.0, n.z), 3.0);
    float transparency = mix(0.55, 0.05, fresnel);

    half3 tint = half3(1.05, 0.85, 0.95);
    half3 seen = half3(refracted.rgb) * tint;
    half3 col  = mix(half3(surface), seen, half(transparency));
    col += half3(1.0, 0.9, 0.95) * half(spec) * half(0.55);
    col += half3(1.0, 0.75, 0.90) * half(fresnel * 0.25);

    float shadow = smoothstep(sdScale * 0.55, 0.0, sd) * (1.0 - coverage);
    half4 layerAt = layer.sample(position);
    half3 bg = layerAt.rgb * half(1.0 - shadow * 0.35);

    half3 outCol = mix(bg, col, half(coverage));
    return half4(outCol, 1.0);
}
