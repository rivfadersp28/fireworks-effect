#include <metal_stdlib>
using namespace metal;

struct RippleFullscreenOut {
    float4 position [[position]];
    float2 uv;
};

struct RippleUniforms {
    float2 resolution;
    float2 videoSize;
    float time;
    uint rippleCount;
    float strength;
    float radius;
    float speed;
    float damping;
    float refraction;
    float waveCount;
    float waveSoftness;
    float fadeSpeed;
    float waveSpacing;
};

struct Ripple {
    float4 originAndStartTime;
    float4 parameters;
};

static float3 degamma(float3 c) {
    return pow(c, float3(2.2));
}

static float3 gamma(float3 c) {
    return pow(c, float3(1.0 / 1.8));
}

vertex RippleFullscreenOut rippleVertex(uint vertexID [[vertex_id]]) {
    float2 positions[6] = {
        float2(-1.0, -1.0),
        float2(1.0, -1.0),
        float2(-1.0, 1.0),
        float2(-1.0, 1.0),
        float2(1.0, -1.0),
        float2(1.0, 1.0)
    };
    float2 uvs[6] = {
        float2(0.0, 1.0),
        float2(1.0, 1.0),
        float2(0.0, 0.0),
        float2(0.0, 0.0),
        float2(1.0, 1.0),
        float2(1.0, 0.0)
    };

    RippleFullscreenOut out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.uv = uvs[vertexID];
    return out;
}

static float2 aspectFillVideoUV(float2 screenUV, float2 resolution, float2 videoSize) {
    float screenAspect = resolution.x / max(resolution.y, 1.0);
    float videoAspect = videoSize.x / max(videoSize.y, 1.0);
    float2 uv = screenUV;

    if (videoAspect > screenAspect) {
        float visibleWidth = screenAspect / videoAspect;
        uv.x = (uv.x - 0.5) * visibleWidth + 0.5;
    } else {
        float visibleHeight = videoAspect / screenAspect;
        uv.y = (uv.y - 0.5) * visibleHeight + 0.5;
    }

    return uv;
}

static float2 rippleOffset(float2 uv, constant RippleUniforms& uniforms, constant Ripple* ripples, thread float& rippleAmount) {
    float aspect = uniforms.resolution.x / max(uniforms.resolution.y, 1.0);
    float2 offset = float2(0.0);
    rippleAmount = 0.0;

    for (uint index = 0; index < uniforms.rippleCount; index++) {
        Ripple ripple = ripples[index];
        float2 origin = ripple.originAndStartTime.xy;
        float age = uniforms.time - ripple.originAndStartTime.z;
        float seed = ripple.originAndStartTime.w;
        float strength = ripple.parameters.x;
        float radius = ripple.parameters.y;
        float speed = ripple.parameters.z;
        float damping = ripple.parameters.w;

        if (age < 0.0 || age > 2.8) {
            continue;
        }

        float2 aspectDelta = uv - origin;
        aspectDelta.x *= aspect;
        float distance = length(aspectDelta);
        if (distance < 0.0001) {
            continue;
        }

        float2 direction = aspectDelta / distance;
        direction.x /= aspect;

        float fadeSpeed = max(uniforms.fadeSpeed, 0.001);
        float progress = saturate(age / 2.35);
        float leadingRadius = progress * radius * speed;
        float life = exp(-age * fadeSpeed * 0.9) * (1.0 - smoothstep(0.82, 1.0, progress));
        float spatialFade = exp(-distance * damping * 0.85);
        float softness = saturate(uniforms.waveSoftness);
        float waveCount = clamp(round(uniforms.waveCount), 1.0, 8.0);
        float width = mix(0.012, 0.08, softness) * radius;
        float rippleValue = 0.0;

        for (int waveIndex = 0; waveIndex < 8; waveIndex++) {
            if (float(waveIndex) >= waveCount) {
                break;
            }

            float spacing = radius * max(uniforms.waveSpacing, 0.001) / max(waveCount, 1.0);
            float ringRadius = leadingRadius - float(waveIndex) * spacing;
            if (ringRadius <= 0.0) {
                continue;
            }

            float ringDistance = abs(distance - ringRadius);
            float ring = exp(-pow(ringDistance / max(width, 0.001), 2.0));
            float fadeBack = mix(1.0, 0.52, float(waveIndex) / max(waveCount - 1.0, 1.0));
            rippleValue += ring * fadeBack;
        }

        rippleValue = saturate(rippleValue) * life * spatialFade * strength * seed;
        offset += direction * rippleValue * uniforms.refraction;
        rippleAmount += rippleValue;
    }

    return offset;
}

fragment float4 rippleFragment(RippleFullscreenOut in [[stage_in]],
                               texture2d<float> videoTexture [[texture(0)]],
                               constant RippleUniforms& uniforms [[buffer(0)]],
                               constant Ripple* ripples [[buffer(1)]]) {
    constexpr sampler videoSampler(mag_filter::linear, min_filter::linear, address::clamp_to_edge);

    float2 screenUV = saturate(in.uv);
    float rippleAmount = 0.0;
    float2 distortion = rippleOffset(screenUV, uniforms, ripples, rippleAmount);
    float2 distortedScreenUV = saturate(screenUV + distortion);
    float2 videoUV = aspectFillVideoUV(distortedScreenUV, uniforms.resolution, uniforms.videoSize);
    float3 color = degamma(videoTexture.sample(videoSampler, videoUV).rgb);

    float shimmer = saturate(rippleAmount * 4.0);
    color *= mix(1.0, 1.08, shimmer);
    color += shimmer * 0.035;
    color = gamma(max(color, 0.0));

    return float4(color, 1.0);
}
