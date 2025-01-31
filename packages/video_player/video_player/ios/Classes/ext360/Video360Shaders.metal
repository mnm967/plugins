#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float3 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

struct Uniforms {
    float4x4 modelViewProjectionMatrix;
};

vertex VertexOut vertexShader(const device VertexIn* vertices [[buffer(0)]],
                            constant Uniforms& uniforms [[buffer(1)]],
                            uint vid [[vertex_id]]) {
    VertexOut out;
    VertexIn in = vertices[vid];
    
    out.position = uniforms.modelViewProjectionMatrix * float4(in.position, 1.0);
    out.texCoord = in.texCoord;
    
    return out;
}

fragment float4 fragmentShader(VertexOut in [[stage_in]],
                             texture2d<float> texture [[texture(0)]]) {
    constexpr sampler textureSampler(mag_filter::linear,
                                    min_filter::linear,
                                    mip_filter::linear);
    
    return texture.sample(textureSampler, in.texCoord);
} 