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
