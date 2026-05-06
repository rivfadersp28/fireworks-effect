#include <metal_stdlib>
using namespace metal;

constant uint particlesPerFirework = 100;
constant uint trailCurveSegments = 6;

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
    float verticalMotion;
    float trailBrightness;
    float activeParticleCount;
    float padding1;
    float padding2;
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

struct TrailOut {
    float4 position [[position]];
    float3 color;
    float along;
    float side;
};

struct FullscreenOut {
    float4 position [[position]];
    float2 uv;
};

static float particleCore(float particleSize) {
    float size = max(particleSize, 0.01);
    return mix(0.0000014, 0.00019, saturate((size - 0.11) / 0.89));
}

static float particleIndexForActiveIndex(uint activeParticleIndex, constant FrameUniforms& uniforms) {
    float activeParticles = max(round(uniforms.activeParticleCount), 1.0);
    float particleScale = float(particlesPerFirework) / activeParticles;
    return floor(float(activeParticleIndex) * particleScale);
}

static float2 fireworkParticleOffset(float i, float sampleTime, float seed, constant FrameUniforms& uniforms) {
    float f = i / float(particlesPerFirework);
    float r = sqrt(1.0 - f * f);
    float th = 2.0 * 0.618033 * 3.14159 * i;
    float hash = sin(seed + i * 85412.243);
    float weight = 1.0 - 0.2 * hash;

    th += hash * 3.0 * 6.28 / float(particlesPerFirework);

    float2 lpos = float2(cos(th), sin(th)) * r;
    lpos.xy *= (1.0 - exp(-3.0 * sampleTime / weight)) * weight;
    lpos.xy *= uniforms.explosionRadius;
    float verticalDrift = sampleTime * 0.3 * weight - sampleTime * (1.0 - exp(-sampleTime * weight)) * 0.6 * weight;
    lpos.y -= verticalDrift * uniforms.verticalMotion;
    return lpos;
}

static float2 fireworkCenter(float2 fireworkPosition, float aspect) {
    return float2(
        (2.0 * fireworkPosition.x - 1.0) * aspect,
        2.0 * fireworkPosition.y - 1.0
    );
}

static float3 fireworkBaseColor(float seed) {
    return float3(0.5) + 0.4 * sin(float3(seed) + float3(0.0, 2.1, -2.1));
}

static float particleIntensity(float i,
                               float sampleTime,
                               float motionTime,
                               float seed,
                               float fadeOutStart,
                               constant FrameUniforms& uniforms) {
    float hash = sin(seed + i * 85412.243);
    float tFadeout = 1.0 - smoothstep(2.65, 3.4, motionTime);
    float intensity = 2e-4;
    intensity *= exp(-uniforms.fadeSpeed * motionTime);
    intensity *= 1.0 - 0.5 * hash;
    intensity *= 1.0 + 10.0 * exp(-20.0 * sampleTime);
    intensity *= clamp(3.0 * tFadeout, 0.0, 1.0);
    if (fadeOutStart >= 0.0) {
        float forcedFade = 1.0 - smoothstep(0.0, 0.3, uniforms.time - fadeOutStart);
        intensity *= forcedFade;
    }
    return intensity;
}

static float4 offscreenPosition() {
    return float4(2.0, 2.0, 0.0, 1.0);
}

vertex ParticleOut fireworksParticleVertex(uint vertexID [[vertex_id]],
                                           constant FrameUniforms& uniforms [[buffer(0)]],
                                           constant Firework* fireworks [[buffer(1)]]) {
    uint activeParticles = max(uint(round(uniforms.activeParticleCount)), 1u);
    uint fireworkIndex = vertexID / activeParticles;
    uint activeParticleIndex = vertexID - fireworkIndex * activeParticles;

    ParticleOut out;
    out.position = offscreenPosition();
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

    float motionTime = t * uniforms.flightSpeed;
    float sampleTime = motionTime;
    if (sampleTime < 0.0) {
        return out;
    }

    float i = particleIndexForActiveIndex(activeParticleIndex, uniforms);
    float2 lpos = fireworkParticleOffset(i, sampleTime, seed, uniforms);
    float aspect = uniforms.resolution.x / uniforms.resolution.y;
    float2 center = fireworkCenter(fireworkPosition, aspect);
    float2 p = center + lpos;

    float normalizedSize = saturate((uniforms.particleSize - 0.11) / 0.89);
    float corePixelSize = mix(10.0, 74.0, normalizedSize);
    float glowRadiusPixels = max(uniforms.glowRadius, corePixelSize * 0.5);
    float pointSize = max(corePixelSize, glowRadiusPixels * 2.0);

    out.position = float4(p.x / aspect, p.y, 0.0, 1.0);
    out.pointSize = pointSize;
    out.color = fireworkBaseColor(seed) * particleIntensity(i, sampleTime, motionTime, seed, fadeOutStart, uniforms);
    out.particleSize = uniforms.particleSize;
    out.corePixelSize = corePixelSize;
    out.glowRadiusPixels = glowRadiusPixels;
    out.spritePixelSize = pointSize;
    return out;
}

vertex TrailOut fireworksTrailVertex(uint vertexID [[vertex_id]],
                                      constant FrameUniforms& uniforms [[buffer(0)]],
                                      constant Firework* fireworks [[buffer(1)]]) {
    uint verticesPerTrail = 6u;
    uint verticesPerParticleTrail = trailCurveSegments * verticesPerTrail;
    uint activeParticles = max(uint(round(uniforms.activeParticleCount)), 1u);
    uint particleTrailID = vertexID / verticesPerParticleTrail;
    uint vertexInParticleTrail = vertexID - particleTrailID * verticesPerParticleTrail;
    uint segmentID = vertexInParticleTrail / verticesPerTrail;
    uint cornerID = vertexInParticleTrail - segmentID * verticesPerTrail;
    uint fireworkIndex = particleTrailID / activeParticles;
    uint activeParticleIndex = particleTrailID - fireworkIndex * activeParticles;

    TrailOut out;
    out.position = offscreenPosition();
    out.color = float3(0.0);
    out.along = 1.0;
    out.side = 0.0;

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

    float motionTime = t * uniforms.flightSpeed;
    float trailLength = 0.68;
    float availableTrail = min(trailLength, motionTime);
    if (motionTime <= 0.01 || availableTrail <= 0.005) {
        return out;
    }

    float i = particleIndexForActiveIndex(activeParticleIndex, uniforms);
    float aspect = uniforms.resolution.x / uniforms.resolution.y;
    float2 center = fireworkCenter(fireworkPosition, aspect);
    float segmentStart = float(segmentID) / float(trailCurveSegments);
    float segmentEnd = float(segmentID + 1u) / float(trailCurveSegments);
    float segmentStartTime = motionTime - segmentStart * availableTrail;
    float segmentEndTime = motionTime - segmentEnd * availableTrail;
    float2 segmentStartPosition = center + fireworkParticleOffset(i, segmentStartTime, seed, uniforms);
    float2 segmentEndPosition = center + fireworkParticleOffset(i, segmentEndTime, seed, uniforms);
    float2 segmentStartClip = float2(segmentStartPosition.x / aspect, segmentStartPosition.y);
    float2 segmentEndClip = float2(segmentEndPosition.x / aspect, segmentEndPosition.y);
    float2 segmentStartPixel = (segmentStartClip * 0.5 + 0.5) * uniforms.resolution;
    float2 segmentEndPixel = (segmentEndClip * 0.5 + 0.5) * uniforms.resolution;
    float2 axis = segmentStartPixel - segmentEndPixel;
    float axisLength = length(axis);
    if (axisLength < 1.0) {
        return out;
    }

    float sides[6] = { -1.0, 1.0, -1.0, -1.0, 1.0, 1.0 };
    float alongs[6] = { 0.0, 0.0, 1.0, 1.0, 0.0, 1.0 };
    float side = sides[cornerID];
    float localAlong = alongs[cornerID];
    float along = mix(segmentStart, segmentEnd, localAlong);
    float2 normal = normalize(float2(-axis.y, axis.x));
    float normalizedSize = saturate((uniforms.particleSize - 0.11) / 0.89);
    float headWidth = mix(7.0, 22.0, normalizedSize);
    float width = mix(headWidth, headWidth * 0.18, along);
    float2 pixel = mix(segmentStartPixel, segmentEndPixel, localAlong) + normal * side * width;
    float2 clip = pixel / uniforms.resolution * 2.0 - 1.0;

    float sampleTime = mix(segmentStartTime, segmentEndTime, localAlong);
    float intensity = particleIntensity(i, sampleTime, motionTime, seed, fadeOutStart, uniforms);
    float3 color = fireworkBaseColor(seed) * intensity * mix(0.68, 0.0, smoothstep(0.0, 1.0, along));

    out.position = float4(clip, 0.0, 1.0);
    out.color = color;
    out.along = along;
    out.side = side;
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

fragment float4 fireworksTrailFragment(TrailOut in [[stage_in]],
                                       constant FrameUniforms& uniforms [[buffer(0)]]) {
    float transverse = exp(-in.side * in.side * 3.2);
    float longitudinal = 1.0 - smoothstep(0.0, 1.0, in.along);
    float trailBoost = (120.0 + uniforms.glowIntensity * 18.0) * 2.0 * uniforms.trailBrightness;
    float3 color = in.color * transverse * longitudinal * trailBoost;
    return float4(color, 1.0);
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
