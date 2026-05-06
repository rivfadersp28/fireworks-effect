#include <metal_stdlib>
using namespace metal;

constant uint particlesPerFirework = 100;
constant uint trailSegments = 20;

struct Firework {
    float4 base;
    float4 fade;
};

struct FrameUniforms {
    float2 resolution;
    float time;
    uint fireworkCount;
    float explosionRadius;
    float particleSize;
    float glowIntensity;
    float glowRadius;
    float particleBlur;
    float fadeSpeed;
    float flightSpeed;
    float trailInstanceCount;
    float activeParticleCount;
    float renderedTrailSegmentCount;
    float padding0;
    float padding1;
};

struct ParticleOut {
    float4 position [[position]];
    float pointSize [[point_size]];
    float3 color;
    float particleSize;
    float corePixelSize;
    float glowRadiusPixels;
    float spritePixelSize;
};

struct FullscreenOut {
    float4 position [[position]];
    float2 uv;
};

static float particleCore(float particleSize) {
    float size = max(particleSize, 0.01);
    return mix(0.0000014, 0.00019, saturate((size - 0.11) / 0.89));
}

vertex ParticleOut fireworksParticleVertex(uint vertexID [[vertex_id]],
                                           constant FrameUniforms& uniforms [[buffer(0)]],
                                           constant Firework* fireworks [[buffer(1)]]) {
    uint activeParticles = max(uint(round(uniforms.activeParticleCount)), 1u);
    uint renderedTrailSegments = max(uint(round(uniforms.renderedTrailSegmentCount)), 1u);
    uint activeSpritesPerFirework = activeParticles * renderedTrailSegments;
    uint fireworkIndex = vertexID / activeSpritesPerFirework;
    uint spriteIndex = vertexID - fireworkIndex * activeSpritesPerFirework;
    uint activeParticleIndex = spriteIndex / renderedTrailSegments;
    uint trailIndex = spriteIndex - activeParticleIndex * renderedTrailSegments;

    ParticleOut out;
    out.position = float4(2.0, 2.0, 0.0, 1.0);
    out.pointSize = 0.0;
    out.color = float3(0.0);
    out.particleSize = uniforms.particleSize;
    out.corePixelSize = 1.0;
    out.glowRadiusPixels = 1.0;
    out.spritePixelSize = 1.0;

    if (fireworkIndex >= uniforms.fireworkCount) {
        return out;
    }

    Firework firework = fireworks[fireworkIndex];
    float2 fireworkPosition = firework.base.xy;
    float startTime = firework.base.z;
    float seed = firework.base.w;
    float fadeOutStart = firework.fade.x;

    float t = uniforms.time - startTime;
    if (t < 0.0 || t > 3.4) {
        return out;
    }

    float maxTrailSegments = clamp(round(uniforms.trailInstanceCount), 1.0, float(trailSegments));
    float trailAmount = float(trailIndex);
    if (trailAmount >= maxTrailSegments) {
        return out;
    }

    float motionTime = t * uniforms.flightSpeed;
    float trailProgress = maxTrailSegments > 1.0 ? trailAmount / (maxTrailSegments - 1.0) : 0.0;
    float trailDuration = 0.56;
    float sampleTime = motionTime - trailProgress * trailDuration;
    if (sampleTime < 0.0) {
        return out;
    }

    float particleScale = float(particlesPerFirework) / float(activeParticles);
    float i = floor(float(activeParticleIndex) * particleScale);
    float f = i / float(particlesPerFirework);
    float r = sqrt(1.0 - f * f);
    float th = 2.0 * 0.618033 * 3.14159 * i;
    float hash = sin(seed + i * 85412.243);
    float weight = 1.0 - 0.2 * hash;

    th += hash * 3.0 * 6.28 / float(particlesPerFirework);

    float2 lpos = float2(cos(th), sin(th)) * r;
    lpos.xy *= (1.0 - exp(-3.0 * sampleTime / weight)) * weight;
    lpos.xy *= uniforms.explosionRadius;
    lpos.y -= sampleTime * 0.3 * weight - sampleTime * (1.0 - exp(-sampleTime * weight)) * 0.6 * weight;

    float aspect = uniforms.resolution.x / uniforms.resolution.y;
    float2 center = float2(
        (2.0 * fireworkPosition.x - 1.0) * aspect,
        2.0 * fireworkPosition.y - 1.0
    );
    float2 p = center + lpos;

    float tFadeout = 1.0 - smoothstep(2.65, 3.4, motionTime);
    float3 baseCol = float3(0.5) + 0.4 * sin(float3(seed) + float3(0.0, 2.1, -2.1));

    float intensity = 2e-4;
    intensity *= exp(-uniforms.fadeSpeed * motionTime);
    intensity *= 1.0 - 0.5 * hash;
    intensity *= 1.0 + 10.0 * exp(-20.0 * sampleTime);
    intensity *= clamp(3.0 * tFadeout, 0.0, 1.0);
    if (fadeOutStart >= 0.0) {
        float forcedFade = 1.0 - smoothstep(0.0, 0.3, uniforms.time - fadeOutStart);
        intensity *= forcedFade;
    }

    float trailFade = trailIndex == 0 ? 1.0 : exp(-trailProgress * 2.35);
    intensity *= trailFade;

    float normalizedSize = saturate((uniforms.particleSize - 0.11) / 0.89);
    float corePixelSize = mix(10.0, 74.0, normalizedSize);
    corePixelSize *= trailIndex == 0 ? 1.0 : mix(0.82, 0.28, trailProgress);
    float glowRadiusPixels = max(uniforms.glowRadius, corePixelSize * 0.5);
    float pointSize = max(corePixelSize, glowRadiusPixels * 2.0);

    out.position = float4(p.x / aspect, p.y, 0.0, 1.0);
    out.pointSize = pointSize;
    out.color = baseCol * intensity;
    out.particleSize = uniforms.particleSize;
    out.corePixelSize = corePixelSize;
    out.glowRadiusPixels = glowRadiusPixels;
    out.spritePixelSize = pointSize;
    return out;
}

fragment float4 fireworksParticleFragment(ParticleOut in [[stage_in]],
                                          float2 pointCoord [[point_coord]],
                                          constant FrameUniforms& uniforms [[buffer(0)]]) {
    float2 centered = pointCoord - 0.5;
    float circleDistance = length(centered) * 2.0;
    if (circleDistance > 1.0) {
        discard_fragment();
    }

    float2 pixelOffset = centered * in.spritePixelSize;
    float pixelDistance = length(pixelOffset);
    float2 q = pixelOffset * (2.0 / uniforms.resolution.y);
    float size = max(in.particleSize, 0.01);
    float atten = size / max(dot(q, q), particleCore(size));
    float blur = saturate(uniforms.particleBlur);
    float blurredAtten = size / max(dot(q, q), particleCore(size) * mix(1.0, 42.0, blur));
    float coreRadiusPixels = max(in.corePixelSize * 0.5, 0.5);
    float blurredCoreRadiusPixels = coreRadiusPixels * mix(1.0, 2.8, blur);
    float coreDistance = pixelDistance / blurredCoreRadiusPixels;
    float core = exp(-coreDistance * coreDistance * mix(5.0, 0.72, blur));

    float glowDistance = pixelDistance / max(in.glowRadiusPixels, 1.0);
    float halo = exp(-glowDistance * glowDistance * 3.0) * uniforms.glowIntensity;

    float3 coreColor = in.color * mix(atten, blurredAtten, blur) * core * mix(0.8, 0.42, blur);
    float3 glowColor = in.color * halo * 2.8;
    return float4(coreColor + glowColor, 1.0);
}

vertex FullscreenOut toneMapVertex(uint vertexID [[vertex_id]]) {
    float2 positions[3] = {
        float2(-1.0, -1.0),
        float2(3.0, -1.0),
        float2(-1.0, 3.0)
    };

    float2 position = positions[vertexID];

    FullscreenOut out;
    out.position = float4(position, 0.0, 1.0);
    out.uv = position * 0.5 + 0.5;
    return out;
}

fragment float4 toneMapFragment(FullscreenOut in [[stage_in]],
                                texture2d<float> accumulation [[texture(0)]]) {
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear, address::clamp_to_edge);
    float3 color = accumulation.sample(textureSampler, in.uv).rgb;

    color = max(color, 0.0);
    color = (color * (2.51 * color + 0.03)) / (color * (2.43 * color + 0.59) + 0.14);
    color = sqrt(saturate(color));
    return float4(color, 1.0);
}
