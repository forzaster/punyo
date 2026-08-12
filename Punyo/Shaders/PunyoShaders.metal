#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// --- Shared helpers ---------------------------------------------------------
//
// The puni is an ellipse with axes = (rx, ry). We compute a normalized
// coordinate `relN = (p - center) / axes`; the base ellipse boundary is then
// `|relN| == 1`. Deformation adds an angular bulge in this normalized space,
// and the SDF is scaled by min(axes) back into approximate point space.
//
// Deformation has two channels, because one is not enough. `deformation` is a
// direction and a magnitude — the lateral bulge of an off-centre poke. `squash`
// is a scalar: how flat the body is being pressed. A float2 cannot express a
// finger pressing straight into the middle, since at the centre there is no
// direction, so the scalar carries that case.

// Squash spreads the silhouette radially. Mirrored in Swift as
// `PunyoPhysics.squashSpread` so the eyes drawn on top track the same shape.
static inline float punyoSquashSpread(float squash) {
    return 1.0 + 0.28 * clamp(squash, 0.0, 1.5);
}

static inline float sdPunyoSilhouette(float2 p,
                                      float2 center,
                                      float2 axes,
                                      float2 deformation,
                                      float squash) {
    // Pressed flat, it spreads. Widening the axes here is what makes the
    // squashed body read as squeezed rather than shrunk.
    float2 sAxes = axes * punyoSquashSpread(squash);
    float2 rel = p - center;
    float2 relN = rel / sAxes;
    float dN = length(relN);
    float sdScale = min(sAxes.x, sAxes.y);
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
                                 float2 deformation,
                                 float squash) {
    float spread = punyoSquashSpread(squash);
    float2 sAxes = axes * spread;
    float sdScale = min(sAxes.x, sAxes.y);
    float sd = sdPunyoSilhouette(p, center, axes, deformation, squash);
    float inside = max(0.0, -sd);
    // Dome height as if the local slice were a hemisphere of radius sdScale.
    // This gives a pseudo-3D bump even on an ellipsoidal silhouette.
    float h = sqrt(max(0.0, sdScale * sdScale - (sdScale - inside) * (sdScale - inside)));
    // Roughly volume preserving: the footprint grew by spread^2, so the dome
    // gives back the same factor in height and the body genuinely flattens
    // instead of just getting bigger.
    return h / (spread * spread);
}

static inline float3 punyoNormal(float2 p,
                                 float2 center,
                                 float2 axes,
                                 float2 deformation,
                                 float squash) {
    const float eps = 1.5;
    float hxP = insideHeight(p + float2(eps, 0.0), center, axes, deformation, squash);
    float hxN = insideHeight(p - float2(eps, 0.0), center, axes, deformation, squash);
    float hyP = insideHeight(p + float2(0.0, eps), center, axes, deformation, squash);
    float hyN = insideHeight(p - float2(0.0, eps), center, axes, deformation, squash);
    float3 grad = float3((hxP - hxN) / (2.0 * eps),
                         (hyP - hyN) / (2.0 * eps),
                         1.0);
    return normalize(float3(-grad.x, -grad.y, grad.z));
}

static inline float punyoCoverage(float sd) {
    const float aa = 1.0;
    return smoothstep(aa, -aa, sd);
}

// --- Metaball field (♾️ pose) -----------------------------------------------
//
// N-lobe scalar field, summed 2D metaballs. F(p) = Σ R_i² / d_i², with d
// floored to keep the value finite at the exact lobe center. Isosurface at
// F(p) == threshold. We render {p: F(p) ≥ threshold} as the silhouette.
//
// Positions and radii are packed into fixed-size arrays because Metal doesn't
// take variable-length uniform arrays through SwiftUI's Shader arguments; we
// pay for a fixed cap (4) unconditionally, which is fine for 2- and 3-lobe
// setups and leaves room for the chain-of-lobes extension without recompiling
// the shader.

#define kPunyoMaxLobes 4

static inline float punyoMetaballField(float2 p,
                                       thread float2 lobes[kPunyoMaxLobes],
                                       thread float  radii[kPunyoMaxLobes],
                                       int count) {
    float sum = 0.0;
    // Loop bound is a runtime int but count is a small uniform — Metal's
    // shader compiler handles the dynamic length cleanly, and the branchless
    // early-out below keeps zero-radius lobes free.
    for (int i = 0; i < kPunyoMaxLobes; ++i) {
        if (i >= count) break;
        float r = radii[i];
        if (r < 0.1) continue;
        float2 d = p - lobes[i];
        // Floor the denominator so the field stays finite at the lobe
        // center. eps set roughly to (r * 0.15)² — the sample is inside
        // the lobe anyway, so the exact value doesn't matter for
        // silhouette; it just needs to not divide by zero.
        float d2 = max(dot(d, d), r * r * 0.02);
        sum += (r * r) / d2;
    }
    return sum;
}

// "SDF proxy" derived from the field, in point units. The field is
// dimensionless (r²/d²), so we scale (threshold - field) by the lobe radius
// to get something whose zero crossing is roughly the silhouette in pixels
// and where `punyoCoverage` gives a stable AA band.
static inline float punyoMetaballSD(float2 p,
                                    thread float2 lobes[kPunyoMaxLobes],
                                    thread float  radii[kPunyoMaxLobes],
                                    int count,
                                    float threshold,
                                    float scale) {
    float f = punyoMetaballField(p, lobes, radii, count);
    return (threshold - f) * scale;
}

// `spread` is punyoSquashSpread(squash), already baked into the lobe radii by
// the caller. It is passed in again only so the dome height can divide it back
// out — the same rough volume preservation the ellipse path does in
// `insideHeight`. Pass 1.0 for an unsquashed field.
static inline float punyoMetaballHeight(float2 p,
                                        thread float2 lobes[kPunyoMaxLobes],
                                        thread float  radii[kPunyoMaxLobes],
                                        int count,
                                        float threshold,
                                        float scale,
                                        float spread) {
    float f = punyoMetaballField(p, lobes, radii, count);
    // Excess above threshold, mapped to a pseudo dome height. The 0.6
    // exponent flattens the peak so lobe centers don't turn into spikes.
    float over = max(0.0, f - threshold);
    // Footprint grew by spread², so the dome gives the same factor back in
    // height: a pressed ♾️ spreads and flattens instead of merely inflating.
    return scale * pow(over, 0.6) / (spread * spread);
}

static inline float3 punyoMetaballNormal(float2 p,
                                         thread float2 lobes[kPunyoMaxLobes],
                                         thread float  radii[kPunyoMaxLobes],
                                         int count,
                                         float threshold,
                                         float scale,
                                         float spread) {
    const float eps = 1.75;
    float hxP = punyoMetaballHeight(p + float2(eps, 0.0), lobes, radii, count, threshold, scale, spread);
    float hxN = punyoMetaballHeight(p - float2(eps, 0.0), lobes, radii, count, threshold, scale, spread);
    float hyP = punyoMetaballHeight(p + float2(0.0, eps), lobes, radii, count, threshold, scale, spread);
    float hyN = punyoMetaballHeight(p - float2(0.0, eps), lobes, radii, count, threshold, scale, spread);
    float3 grad = float3((hxP - hxN) / (2.0 * eps),
                         (hyP - hyN) / (2.0 * eps),
                         1.0);
    return normalize(float3(-grad.x, -grad.y, grad.z));
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
    float squash,
    float viscosity,
    float elasticity
) {
    float sd = sdPunyoSilhouette(position, center, axes, deformation, squash);
    float coverage = punyoCoverage(sd);
    if (coverage < 0.001) {
        return currentColor;
    }

    float3 n = punyoNormal(position, center, axes, deformation, squash);
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
    float2 relN = (position - center) / (axes * punyoSquashSpread(squash));
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
    float squash,
    float stamina,
    float2 velocity,
    float3 baseColor,
    float3 innerColor,
    float4 optics,
    float4 surface
) {
    float tired = clamp(1.0 - stamina, 0.0, 1.0);
    float sdScale = min(axes.x, axes.y) * punyoSquashSpread(squash);
    float sd = sdPunyoSilhouette(position, center, axes, deformation, squash);
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

    float3 n = punyoNormal(position, center, axes, deformation, squash);
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

// --- Metaball material (♾️ pose) --------------------------------------------
//
// Same appearance uniforms as punyo_material, but the silhouette comes from
// a summed metaball field instead of a single ellipse. Uses up to 4 lobes:
// 2 for the base ♾️, 3 for an explicit constriction control, 4 for a chain
// extension. Reads the pose data as four float2 lobe positions + one float4
// of radii + a count + a threshold.
//
// The lighting path is a trimmed version of the material shader: pseudo SSS,
// specular, fresnel — but no refraction or metallic environment sampling.
// Those two effects sample the layer with an offset that assumes a coherent
// dome; on a peanut / dumbbell shape the sample lands in nonsense and reads
// as smeared halos. Cut them here and keep the pose visually honest.
//
// Takes the same geometry prefix as every other entry point, `deformation`
// and `axes` included, even though the silhouette here comes from the lobes
// rather than the ellipse. Keeping one prefix for all techniques is what makes
// the Swift-side argument list checkable — a per-technique prefix is how an
// argument order quietly drifts and corrupts everything after it.
//
// `deformation` is genuinely unused: the lateral bulge is an ellipse-space
// angular term with no meaning on a two-lobe field. `squash` is not — it
// scales the lobe radii exactly as it scales the ellipse axes, so a press
// still reads while the pose is held.

[[ stitchable ]] half4 punyo_infinityMaterial(
    float2 position,
    SwiftUI::Layer layer,
    float4 boundingRect,
    float time,
    float2 fingerPos,
    float fingerActive,
    float2 center,
    float2 deformation,
    float2 axes,
    float squash,
    float stamina,
    float2 lobe0,
    float2 lobe1,
    float2 lobe2,
    float2 lobe3,
    float4 lobeRadii,
    float lobeCount,
    float threshold,
    float3 baseColor,
    float3 innerColor,
    float4 optics,
    float4 surface
) {
    // Squash fattens every lobe by the same factor the ellipse axes take, so
    // pressing a held ♾️ spreads the lobes and thickens the waist instead of
    // doing nothing at all. The dome height divides the factor back out (see
    // punyoMetaballHeight) so it flattens rather than inflates.
    float spread = punyoSquashSpread(squash);
    float2 lobes[kPunyoMaxLobes] = { lobe0, lobe1, lobe2, lobe3 };
    float  radii[kPunyoMaxLobes] = { lobeRadii.x * spread, lobeRadii.y * spread,
                                     lobeRadii.z * spread, lobeRadii.w * spread };
    int count = clamp(int(round(lobeCount)), 0, kPunyoMaxLobes);

    // Scale for the SD proxy — anchored on the biggest lobe so AA and normal
    // steps stay stable when the two big lobes are the same size and a
    // small constriction lobe is added.
    float rMax = max(max(radii[0], radii[1]), max(radii[2], radii[3]));
    float scale = max(4.0, rMax);

    float sd = punyoMetaballSD(position, lobes, radii, count, threshold, scale);
    float coverage = punyoCoverage(sd);
    if (coverage < 0.001) {
        return layer.sample(position);
    }

    float tired = clamp(1.0 - stamina, 0.0, 1.0);
    float bodyOpacity  = optics.w;
    float translucency = optics.x;
    float fresnelAmt   = optics.z;
    float specStrength = surface.x;
    float specPower    = surface.y;
    float grain        = surface.w;

    float3 n = punyoMetaballNormal(position, lobes, radii, count, threshold, scale, spread);

    if (grain > 0.001) {
        float2 gp = (position - center) * 0.25;
        float nx = punyoFBM(gp + float2(1.7, 0.0)) - punyoFBM(gp - float2(1.7, 0.0));
        float ny = punyoFBM(gp + float2(0.0, 1.7)) - punyoFBM(gp - float2(0.0, 1.7));
        n = normalize(n + float3(nx, ny, 0.0) * grain * 0.7);
    }

    // Thickness from the height field, normalized against the largest lobe
    // so lighting reads consistently across radii.
    float h = punyoMetaballHeight(position, lobes, radii, count, threshold, scale, spread);
    float thickness = clamp(h / max(scale, 0.001), 0.0, 1.0);

    float3 L = normalize(float3(-0.4, -0.55, 0.75));
    float3 V = float3(0.0, 0.0, 1.0);
    float3 H = normalize(L + V);

    const float wrap = 0.3;
    float diff = max(0.0, (dot(n, L) + wrap) / (1.0 + wrap));
    float spec = pow(max(0.0, dot(n, H)), max(1.0, specPower))
               * specStrength * (1.0 - tired * 0.5);
    float fresnel = pow(1.0 - max(0.0, n.z), 3.0) * fresnelAmt;

    float3 base = punyoFatigueTint(baseColor, tired);
    float backFacing = max(0.0, dot(-n, L));
    float transmission = pow(1.0 - thickness, 2.5);
    float3 sss = punyoFatigueTint(innerColor, tired)
               * (backFacing * transmission * translucency * 1.6);

    float3 col = base * (0.30 + 0.70 * diff) + sss;
    col += float3(1.0, 0.94, 0.97) * spec;
    col += base * fresnel * 0.55;

    if (grain > 0.001) {
        float speck = punyoFBM((position - center) * 0.9) - 0.5;
        col *= 1.0 + speck * grain * 0.45;
    }

    // Contact shadow around the whole outline — same trick as the ellipse
    // shader, but the SD proxy is only nominally in pixels, so we bias the
    // fall-off with `scale` rather than a hardcoded radius.
    float shadow = smoothstep(scale * 0.55, 0.0, sd) * (1.0 - coverage);
    float3 bg = float3(layer.sample(position).rgb) * (1.0 - shadow * 0.35);

    float bodyAlpha = coverage * bodyOpacity;
    float3 outCol = mix(bg, col, bodyAlpha);
    return half4(half3(outCol), 1.0);
}

// --- Toon-shaded material ---------------------------------------------------
// Same appearance uniforms as punyo_material, but rendered in a toon / mascot
// style: quantized diffuse bands, hard specular hotspot, dark ink outline,
// soft blush cheeks. Refraction and metallic sampling are dropped (a toon
// look wants flat shading, not the background bent through it), which lets
// this run as a colorEffect rather than a layerEffect.

[[ stitchable ]] half4 punyo_toonMaterial(
    float2 position,
    half4 currentColor,
    float4 boundingRect,
    float time,
    float2 fingerPos,
    float fingerActive,
    float2 center,
    float2 deformation,
    float2 axes,
    float squash,
    float stamina,
    float2 velocity,
    float3 baseColor,
    float3 innerColor,
    float4 optics,
    float4 surface
) {
    float tired = clamp(1.0 - stamina, 0.0, 1.0);
    float sd = sdPunyoSilhouette(position, center, axes, deformation, squash);
    float coverage = punyoCoverage(sd);
    if (coverage < 0.001) {
        return currentColor;
    }

    float bodyOpacity  = optics.w;
    float specStrength = surface.x;
    float grain        = surface.w;

    float3 n = punyoNormal(position, center, axes, deformation, squash);
    float sdScale = min(axes.x, axes.y) * punyoSquashSpread(squash);
    float inside = max(0.0, -sd);
    float thickness = clamp(inside / max(sdScale, 0.001), 0.0, 1.0);

    // Same rim-fray treatment as the material shader, so sand/smoke materials
    // don't turn into a hard circle when rendered toon-style.
    if (grain > 0.001) {
        float2 gp = (position - center) * 0.25;
        float nx = punyoFBM(gp + float2(1.7, 0.0)) - punyoFBM(gp - float2(1.7, 0.0));
        float ny = punyoFBM(gp + float2(0.0, 1.7)) - punyoFBM(gp - float2(0.0, 1.7));
        n = normalize(n + float3(nx, ny, 0.0) * grain * 0.5);

        float edge = 1.0 - thickness;
        float2 fp = (position - center) * 0.08 + float2(time * 0.06, 0.0);
        float fray = punyoFBM(fp);
        coverage *= clamp(1.0 - grain * edge * edge * (0.9 - fray), 0.0, 1.0);
    }

    float3 L = normalize(float3(-0.35, -0.55, 0.75));
    float3 V = float3(0.0, 0.0, 1.0);
    float3 H = normalize(L + V);
    float diff = dot(n, L);
    float spec = pow(max(0.0, dot(n, H)), 40.0);

    // Three lit bands + a shadow band. Thresholds smoothed just enough that
    // curved silhouettes don't alias.
    float d1 = smoothstep(0.10, 0.15, diff);
    float d2 = smoothstep(0.42, 0.48, diff);
    float d3 = smoothstep(0.78, 0.83, diff);
    float toonDiff = 0.35 + 0.20 * d1 + 0.25 * d2 + 0.20 * d3;

    float3 base   = punyoFatigueTint(baseColor, tired);
    float3 shadow = punyoFatigueTint(innerColor, tired) * 0.75;
    float3 body   = mix(shadow, base, toonDiff);

    // Ink outline: darken pixels within a narrow ring inside the silhouette.
    float outline = 1.0 - smoothstep(1.5, 4.0, -sd);
    body *= mix(1.0, 0.30, outline);

    // Hard specular hotspot, weighted by the material's spec strength so glass
    // and mercury still read as shinier than mochi.
    float toonSpec = smoothstep(0.55, 0.62, spec);
    body += float3(1.0, 0.98, 1.0) * toonSpec * (0.55 + 0.45 * specStrength);

    // Two soft blush spots on the upper dome.
    float2 blushDir1 = float2(-0.35, -0.15);
    float2 blushDir2 = float2( 0.35, -0.15);
    float2 relN = (position - center) / (axes * punyoSquashSpread(squash));
    float b1 = smoothstep(0.32, 0.08, length(relN - blushDir1));
    float b2 = smoothstep(0.32, 0.08, length(relN - blushDir2));
    body = mix(body, body * float3(1.15, 0.78, 0.88), min(1.0, (b1 + b2) * 0.5));

    if (grain > 0.001) {
        float speck = punyoFBM((position - center) * 0.9) - 0.5;
        body *= 1.0 + speck * grain * 0.35;
    }

    float bodyAlpha = coverage * bodyOpacity;
    half3 outCol = mix(currentColor.rgb, half3(body), half(bodyAlpha));
    return half4(outCol, max(currentColor.a, half(bodyAlpha)));
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
    float squash,
    float viscosity,
    float elasticity
) {
    float sd = sdPunyoSilhouette(position, center, axes, deformation, squash);
    float coverage = punyoCoverage(sd);
    if (coverage < 0.001) {
        return currentColor;
    }

    float3 n = punyoNormal(position, center, axes, deformation, squash);
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

    float sdScale = min(axes.x, axes.y) * punyoSquashSpread(squash);
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
    float squash,
    float viscosity,
    float elasticity
) {
    float sd = sdPunyoSilhouette(position, center, axes, deformation, squash);
    float coverage = punyoCoverage(sd);
    if (coverage < 0.001) {
        return currentColor;
    }

    float3 n = punyoNormal(position, center, axes, deformation, squash);
    float sdScale = min(axes.x, axes.y) * punyoSquashSpread(squash);
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
    float squash,
    float viscosity,
    float elasticity
) {
    float sd = sdPunyoSilhouette(position, center, axes, deformation, squash);
    float coverage = punyoCoverage(sd);
    if (coverage < 0.001) {
        return layer.sample(position);
    }

    float3 n = punyoNormal(position, center, axes, deformation, squash);
    float sdScale = min(axes.x, axes.y) * punyoSquashSpread(squash);
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
