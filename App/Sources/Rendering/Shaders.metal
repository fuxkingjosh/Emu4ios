#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

struct ScreenUniforms {
    int filter;        // index into ScreenFilter.allCases
    float intensity;   // 0...1
    float2 sourceSize; // emulator pixels
    float2 outputSize; // drawable pixels
    float time;
};

vertex VertexOut screen_vertex(uint vid [[vertex_id]]) {
    // Full-screen triangle strip.
    float2 positions[4] = { float2(-1, -1), float2(1, -1), float2(-1, 1), float2(1, 1) };
    float2 uvs[4] = { float2(0, 1), float2(1, 1), float2(0, 0), float2(1, 0) };
    VertexOut out;
    out.position = float4(positions[vid], 0, 1);
    out.uv = uvs[vid];
    return out;
}

static float luma(float3 c) { return dot(c, float3(0.299, 0.587, 0.114)); }

static float3 paletteLookup(float l, float3 p0, float3 p1, float3 p2, float3 p3) {
    if (l < 0.25) return p0;
    if (l < 0.5) return p1;
    if (l < 0.75) return p2;
    return p3;
}

fragment float4 screen_fragment(VertexOut in [[stage_in]],
                                texture2d<float> tex [[texture(0)]],
                                constant ScreenUniforms& u [[buffer(0)]]) {
    constexpr sampler nearest(filter::nearest, address::clamp_to_edge);
    constexpr sampler linear(filter::linear, address::clamp_to_edge);
    float2 uv = in.uv;
    float k = clamp(u.intensity, 0.0, 1.0);

    switch (u.filter) {
    case 1: { // smooth
        return float4(tex.sample(linear, uv).rgb, 1);
    }
    case 2: { // CRT: slight curve, scanlines, shadow mask, vignette
        float2 cc = uv - 0.5;
        float dist = dot(cc, cc) * 0.12 * k;
        uv = uv + cc * dist;
        if (uv.x < 0 || uv.x > 1 || uv.y < 0 || uv.y > 1) return float4(0, 0, 0, 1);
        float3 color = tex.sample(linear, uv).rgb;
        float scan = 0.5 + 0.5 * cos(uv.y * u.sourceSize.y * 6.28318);
        color *= mix(1.0, 0.65 + 0.35 * scan, k);
        int column = int(in.position.x) % 3;
        float3 mask = column == 0 ? float3(1.0, 0.8, 0.8) : (column == 1 ? float3(0.8, 1.0, 0.8) : float3(0.8, 0.8, 1.0));
        color *= mix(float3(1), mask, k * 0.6);
        float vignette = smoothstep(0.85, 0.25, length(cc) * 1.1);
        color *= mix(1.0, vignette, k * 0.7);
        return float4(color * (1.0 + 0.25 * k), 1);
    }
    case 3: { // LCD grid
        float3 color = tex.sample(nearest, uv).rgb;
        float2 cell = fract(uv * u.sourceSize);
        float edge = step(0.12, cell.x) * step(0.12, cell.y);
        color *= mix(1.0, 0.55 + 0.45 * edge, k);
        return float4(color, 1);
    }
    case 4: { // Original Game Boy green
        float l = luma(tex.sample(nearest, uv).rgb);
        float3 shade = paletteLookup(l, float3(0.06, 0.22, 0.06), float3(0.19, 0.38, 0.19),
                                     float3(0.55, 0.67, 0.06), float3(0.61, 0.74, 0.06));
        float2 cell = fract(uv * u.sourceSize);
        float grid = step(0.1, cell.x) * step(0.1, cell.y);
        shade *= mix(1.0, 0.88 + 0.12 * grid, k);
        return float4(shade, 1);
    }
    case 5: { // Game Boy Pocket
        float l = luma(tex.sample(nearest, uv).rgb);
        float3 shade = paletteLookup(l, float3(0.0), float3(0.33, 0.33, 0.33),
                                     float3(0.66, 0.66, 0.66), float3(0.77, 0.81, 0.63));
        return float4(mix(tex.sample(nearest, uv).rgb, shade, k), 1);
    }
    case 6: { // Handheld color correction (darker, less saturated like the original LCD)
        float3 c = tex.sample(nearest, uv).rgb;
        float3 lcd = pow(c, float3(2.2));
        float3 corrected = float3(
            dot(lcd, float3(0.82, 0.24, -0.06)),
            dot(lcd, float3(0.09, 0.67, 0.24)),
            dot(lcd, float3(0.17, 0.10, 0.73)));
        corrected = pow(clamp(corrected, 0.0, 1.0), float3(1.0 / 2.0));
        return float4(mix(c, corrected, k), 1);
    }
    case 7: { // scanlines
        float3 color = tex.sample(nearest, uv).rgb;
        float line = fract(uv.y * u.sourceSize.y);
        color *= mix(1.0, line < 0.5 ? 1.0 : 0.6, k);
        return float4(color, 1);
    }
    case 8: { // sharp but smooth: crisp pixels, softened only at their edges
        float2 texel = uv * u.sourceSize;
        float2 scale = max(u.outputSize / u.sourceSize, float2(1.0));
        float2 region = 0.5 - 0.5 / scale;
        float2 f = fract(texel);
        float2 center = floor(texel) + 0.5;
        float2 offset = (clamp((f - 0.5 - region) / (1.0 - 2.0 * region + 1e-5), 0.0, 1.0)
                       - clamp((0.5 - f - region) / (1.0 - 2.0 * region + 1e-5), 0.0, 1.0)) * 0.5;
        return float4(tex.sample(linear, (center + offset) / u.sourceSize).rgb, 1);
    }
    case 9: { // dot matrix: each pixel is a round dot
        float3 color = tex.sample(nearest, uv).rgb;
        float2 cell = fract(uv * u.sourceSize) - 0.5;
        float dotMask = smoothstep(0.5, 0.36, length(cell));
        float3 background = color * 0.18;
        return float4(mix(color, mix(background, color, dotMask), k), 1);
    }
    case 10: { // VHS: color bleed, wobble and tracking noise
        float wobble = sin(uv.y * 40.0 + u.time * 3.0) * 0.0015 * k;
        float noiseLine = step(0.995, fract(sin(floor(uv.y * 120.0 + u.time * 20.0) * 43758.5453)));
        float2 uv2 = float2(uv.x + wobble + noiseLine * 0.01 * k, uv.y);
        float r = tex.sample(linear, uv2 + float2(0.004 * k, 0)).r;
        float g = tex.sample(linear, uv2).g;
        float b = tex.sample(linear, uv2 - float2(0.004 * k, 0)).b;
        float3 color = float3(r, g, b);
        float grain = fract(sin(dot(uv * u.time, float2(12.9898, 78.233))) * 43758.5453);
        color += (grain - 0.5) * 0.06 * k;
        color *= 1.0 - 0.15 * k * step(0.5, fract(uv.y * u.sourceSize.y * 0.5));
        return float4(color, 1);
    }
    case 11: { // handheld LCD: red/green/blue subpixel stripes with a faint grid
        float3 color = tex.sample(nearest, uv).rgb;
        float2 cell = fract(uv * u.sourceSize);
        float3 mask = cell.x < 0.333 ? float3(1.0, 0.35, 0.35) : (cell.x < 0.666 ? float3(0.35, 1.0, 0.35) : float3(0.35, 0.35, 1.0));
        float grid = step(0.08, cell.y);
        color = mix(color, color * mask * 1.6 * grid, k * 0.8);
        return float4(color, 1);
    }
    default: // sharp pixels
        return float4(tex.sample(nearest, uv).rgb, 1);
    }
}
