#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// --- Shared helpers ---------------------------------------------------------

// Signed distance to the puni silhouette in view (point) space.
// The silhouette is a circle radius `r` around `center`, deformed by adding a
// cosine bulge in the direction of `deformation` (bulges toward finger side).
static inline float sdPunyoSilhouette(float2 p,
                                      float2 center,
                                      float r,
                                      float2 deformation) {
    float2 rel = p - center;
    float d = length(rel);
    float dmag = length(deformation);
    float bulge = 0.0;
    if (dmag > 0.0001) {
        float2 dn = deformation / dmag;
        float2 relDir = rel / max(d, 0.0001);
        float cosang = dot(relDir, dn);
        bulge = dmag * cosang * 0.55;
    }
    return d - (r + bulge);
}

// Pseudo-3D normal derived from a height-field: h(p) = sqrt(r^2 - inside^2)
// where inside = -sd. Gradient via central differences on the height field.
static inline float3 punyoNormal(float2 p,
                                 float2 center,
                                 float r,
                                 float2 deformation) {
    const float eps = 1.5;
    float sdC = sdPunyoSilhouette(p, center, r, deformation);
    float insideC = max(0.0, -sdC);
    // Neighbors
    float sdxP = sdPunyoSilhouette(p + float2(eps, 0.0), center, r, deformation);
    float sdxN = sdPunyoSilhouette(p - float2(eps, 0.0), center, r, deformation);
    float sdyP = sdPunyoSilhouette(p + float2(0.0, eps), center, r, deformation);
    float sdyN = sdPunyoSilhouette(p - float2(0.0, eps), center, r, deformation);
    float insideXP = max(0.0, -sdxP);
    float insideXN = max(0.0, -sdxN);
    float insideYP = max(0.0, -sdyP);
    float insideYN = max(0.0, -sdyN);
    float hC  = sqrt(max(0.0, r * r - (r - insideC ) * (r - insideC )));
    (void)hC;
    float hxP = sqrt(max(0.0, r * r - (r - insideXP) * (r - insideXP)));
    float hxN = sqrt(max(0.0, r * r - (r - insideXN) * (r - insideXN)));
    float hyP = sqrt(max(0.0, r * r - (r - insideYP) * (r - insideYP)));
    float hyN = sqrt(max(0.0, r * r - (r - insideYN) * (r - insideYN)));
    // Height increases inward, so a negative gradient points "up" the dome.
    float3 grad = float3((hxP - hxN) / (2.0 * eps),
                         (hyP - hyN) / (2.0 * eps),
                         1.0);
    return normalize(float3(-grad.x, -grad.y, grad.z));
}

// Coverage with pixel-sized AA at the silhouette edge.
static inline float punyoCoverage(float sd) {
    const float aa = 1.0;
    return smoothstep(aa, -aa, sd);
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
    float radius,
    float viscosity,
    float elasticity
) {
    float sd = sdPunyoSilhouette(position, center, radius, deformation);
    float coverage = punyoCoverage(sd);
    if (coverage < 0.001) {
        return currentColor;
    }

    float3 n = punyoNormal(position, center, radius, deformation);

    // Light from upper-left, slightly toward camera.
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

    // Soft contact shadow just outside the silhouette (only visible on the
    // background because coverage < 1 there).
    float shadow = smoothstep(radius * 0.55, 0.0, sd) * (1.0 - coverage);
    half3 bg = currentColor.rgb * half(1.0 - shadow * 0.35);

    half3 outCol = mix(bg, half3(col), half(coverage));
    return half4(outCol, max(currentColor.a, half(coverage)));
}

// --- Technique 2: SDF + pseudo SSS -----------------------------------------
// Adds a translucent core: light enters from the back, scatters through the
// dome, and re-emerges toward the camera. Approximated with:
//   - a wrap-around Lambert (light continues past terminator)
//   - a back-light term computed from the height at the pixel (thicker = more
//     absorption, thinner rim = more glow)
// The result reads as mochi/jelly: the rim glows warm and the core keeps a
// deep saturated tint.

[[ stitchable ]] half4 punyo_sdfSSS(
    float2 position,
    half4 currentColor,
    float4 boundingRect,
    float time,
    float2 fingerPos,
    float fingerActive,
    float2 center,
    float2 deformation,
    float radius,
    float viscosity,
    float elasticity
) {
    float sd = sdPunyoSilhouette(position, center, radius, deformation);
    float coverage = punyoCoverage(sd);
    if (coverage < 0.001) {
        return currentColor;
    }

    float3 n = punyoNormal(position, center, radius, deformation);

    // Same key light as the base technique.
    float3 L = normalize(float3(-0.4, -0.55, 0.75));
    float3 V = float3(0.0, 0.0, 1.0);
    float3 H = normalize(L + V);

    // Wrap Lambert: light "wraps" 30% past the terminator, softens shading.
    const float wrap = 0.3;
    float diff = max(0.0, (dot(n, L) + wrap) / (1.0 + wrap));
    float spec = pow(max(0.0, dot(n, H)), 42.0);

    // Approximate thickness at this pixel: 0 at rim → 1 at core.
    float inside = max(0.0, -sd);
    float thickness = clamp(inside / max(radius, 0.001), 0.0, 1.0);
    // How much of the light path is aligned with the view? Back-lit glow uses
    // the opposite hemisphere from the viewer.
    float backFacing = max(0.0, dot(-n, L));
    // Thin regions transmit more; add a soft cosine ramp on the back-facing
    // component. Absorption grows with thickness.
    float transmission = pow(1.0 - thickness, 2.5);
    float sssGlow = backFacing * transmission;

    // Colors: warm surface, warmer/saturated inner glow.
    float3 base    = float3(0.86, 0.44, 0.78);
    float3 inner   = float3(1.00, 0.55, 0.65);
    float3 rimCol  = float3(1.00, 0.75, 0.85);

    float3 surface = base * (0.30 + 0.70 * diff);
    float3 sss     = inner * sssGlow * 1.4;
    float rim      = pow(1.0 - max(0.0, n.z), 2.6);
    float3 col     = surface + sss + rimCol * rim * 0.35 + float3(1.0, 0.9, 0.95) * spec * 0.55;

    // Soft contact shadow.
    float shadow = smoothstep(radius * 0.55, 0.0, sd) * (1.0 - coverage);
    half3 bg = currentColor.rgb * half(1.0 - shadow * 0.35);

    half3 outCol = mix(bg, half3(col), half(coverage));
    return half4(outCol, max(currentColor.a, half(coverage)));
}
