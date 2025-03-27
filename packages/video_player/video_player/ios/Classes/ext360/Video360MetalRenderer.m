#import "Video360MetalRenderer.h"
#import <simd/simd.h>

// Constants
static const float FIELD_OF_VIEW = 90.0f;

// Vertex structure
typedef struct {
    vector_float3 position;  // 12 bytes (3 * 4)
    vector_float2 texCoord;  // 8 bytes (2 * 4)
} Vertex;                    // Total: 20 bytes

// Uniform buffer structure
typedef struct {
    matrix_float4x4 modelViewProjectionMatrix;
} Uniforms;

@implementation Video360MetalRenderer {
    id<MTLDevice> _device;
    id<MTLRenderPipelineState> _pipelineState;
    id<MTLBuffer> _vertexBuffer;
    id<MTLBuffer> _indexBuffer;
    id<MTLBuffer> _uniformBuffer;
    
    CVMetalTextureCacheRef _textureCache;
    
    float _roll;
    float _pitch;
    float _yaw;
    
    vector_uint2 _viewportSize;
    Mesh *_mesh;
    NSUInteger _vertexCount;
    NSUInteger _indexCount;
}

- (instancetype)initWithDevice:(id<MTLDevice>)device {
    self = [super init];
    if (self) {
        _device = device;
        _roll = 0.0f;
        _pitch = 0.0f;
        _yaw = 0.0f;
        
        [self setupPipeline];
        [self setupTextureCache];
    }
    return self;
}

- (void)setupPipeline {
    // Create shader source
    NSString *shaderSource = @"#include <metal_stdlib>\n"
                            "using namespace metal;\n"
                            "\n"
                            "struct VertexIn {\n"
                            "    float3 position [[attribute(0)]];\n"
                            "    float2 texCoord [[attribute(1)]];\n"
                            "};\n"
                            "\n"
                            "struct VertexOut {\n"
                            "    float4 position [[position]];\n"
                            "    float2 texCoord;\n"
                            "};\n"
                            "\n"
                            "struct Uniforms {\n"
                            "    float4x4 modelViewProjectionMatrix;\n"
                            "};\n"
                            "\n"
                            "vertex VertexOut vertexShader(const VertexIn vertex_in [[stage_in]],\n"
                            "                            constant Uniforms &uniforms [[buffer(1)]]) {\n"
                            "    VertexOut out;\n"
                            "    out.position = uniforms.modelViewProjectionMatrix * float4(vertex_in.position, 1.0);\n"
                            "    out.texCoord = vertex_in.texCoord;\n"
                            "    return out;\n"
                            "}\n"
                            "\n"
                            "fragment float4 fragmentShader(VertexOut in [[stage_in]],\n"
                            "                             texture2d<float> texture [[texture(0)]]) {\n"
                            "    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);\n"
                            "    return texture.sample(textureSampler, in.texCoord);\n"
                            "}";
    
    NSError *error = nil;
    id<MTLLibrary> library = [_device newLibraryWithSource:shaderSource options:nil error:&error];
    if (!library) {
        NSLog(@"Failed to create shader library: %@", error);
        return;
    }
    
    id<MTLFunction> vertexFunction = [library newFunctionWithName:@"vertexShader"];
    id<MTLFunction> fragmentFunction = [library newFunctionWithName:@"fragmentShader"];
    
    if (!vertexFunction || !fragmentFunction) {
        NSLog(@"Failed to create shader functions");
        return;
    }
    
    // Create vertex descriptor
    MTLVertexDescriptor *vertexDescriptor = [[MTLVertexDescriptor alloc] init];
    
    // Position attribute
    vertexDescriptor.attributes[0].format = MTLVertexFormatFloat3;
    vertexDescriptor.attributes[0].offset = 0;
    vertexDescriptor.attributes[0].bufferIndex = 0;
    
    // Texture coordinate attribute
    vertexDescriptor.attributes[1].format = MTLVertexFormatFloat2;
    vertexDescriptor.attributes[1].offset = sizeof(float) * 3;
    vertexDescriptor.attributes[1].bufferIndex = 0;
    
    // Single interleaved buffer layout
    vertexDescriptor.layouts[0].stride = sizeof(float) * 5;
    vertexDescriptor.layouts[0].stepRate = 1;
    vertexDescriptor.layouts[0].stepFunction = MTLVertexStepFunctionPerVertex;
    
    // Create pipeline state descriptor
    MTLRenderPipelineDescriptor *pipelineStateDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineStateDescriptor.label = @"360 Video Pipeline";
    pipelineStateDescriptor.vertexFunction = vertexFunction;
    pipelineStateDescriptor.fragmentFunction = fragmentFunction;
    pipelineStateDescriptor.vertexDescriptor = vertexDescriptor;
    pipelineStateDescriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    pipelineStateDescriptor.colorAttachments[0].blendingEnabled = YES;
    pipelineStateDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    pipelineStateDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    pipelineStateDescriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorSourceAlpha;
    pipelineStateDescriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    
    _pipelineState = [_device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor error:&error];
    if (!_pipelineState) {
        NSLog(@"Failed to create pipeline state: %@", error);
        return;
    }
}

- (void)setupTextureCache {
    CVReturn result = CVMetalTextureCacheCreate(kCFAllocatorDefault,
                                              nil,
                                              _device,
                                              nil,
                                              &_textureCache);
    if (result != kCVReturnSuccess) {
        NSLog(@"Failed to create Metal texture cache");
    }
}

- (void)configureSurface:(Mesh *)mesh {
    if (!mesh) {
        NSLog(@"Warning: Attempting to configure with nil mesh");
        return;
    }
    _mesh = mesh;
    [self setupVertexBuffer];
}

- (void)setupVertexBuffer {
    if (!_mesh) return;
    
    // Get mesh data using the proper methods
    float *vertices = NULL;
    uint16_t *indices = NULL;
    NSUInteger vertexCount = 0, indexCount = 0;
    
    @try {
        [_mesh getVertices:&vertices count:&vertexCount];
        [_mesh getIndices:&indices count:&indexCount];
    } @catch (NSException *exception) {
        NSLog(@"Exception getting mesh data: %@", exception);
        if (vertices) free(vertices);
        if (indices) free(indices);
        return;
    }
    
    // Validate vertex data
    if (!vertices || vertexCount == 0) {
        NSLog(@"Invalid vertex data");
        if (indices) free(indices);
        return;
    }
    
    _vertexCount = vertexCount / 5;  // Each vertex has 5 floats (3 for position, 2 for texture)
    _indexCount = indexCount;
    
    if (_vertexCount == 0) {
        NSLog(@"No vertices in mesh");
        free(vertices);
        if (indices) free(indices);
        return;
    }
    
    // Create vertex buffer - each vertex has position (3 floats) and texture coordinates (2 floats)
    const size_t vertexSize = sizeof(Vertex);  // 20 bytes per vertex
    const size_t bufferSize = _vertexCount * vertexSize;
    
    // Convert the float array to Vertex array
    Vertex *vertexData = (Vertex *)malloc(bufferSize);
    if (!vertexData) {
        NSLog(@"Failed to allocate memory for vertex data");
        free(vertices);
        if (indices) free(indices);
        return;
    }
    
    for (NSUInteger i = 0; i < _vertexCount; i++) {
        NSUInteger srcIdx = i * 5;  // Source index in the float array
        vertexData[i].position = (vector_float3){
            vertices[srcIdx],     // X
            vertices[srcIdx + 1], // Y
            vertices[srcIdx + 2]  // Z
        };
        vertexData[i].texCoord = (vector_float2){
            vertices[srcIdx + 3], // U
            vertices[srcIdx + 4]  // V
        };
    }
    
    // Create vertex buffer
    _vertexBuffer = [_device newBufferWithBytes:vertexData
                                       length:bufferSize
                                      options:MTLResourceStorageModeShared];
    free(vertexData);
    free(vertices);
    
    if (!_vertexBuffer) {
        NSLog(@"Failed to create vertex buffer");
        if (indices) free(indices);
        return;
    }
    
    // Create index buffer
    if (indices && indexCount > 0) {
        _indexBuffer = [_device newBufferWithBytes:indices
                                         length:indexCount * sizeof(uint16_t)
                                        options:MTLResourceStorageModeShared];
        if (!_indexBuffer) {
            NSLog(@"Failed to create index buffer");
        }
    }
    
    if (indices) free(indices);
    
    // Ensure uniform buffer exists
    if (!_uniformBuffer) {
        _uniformBuffer = [_device newBufferWithLength:sizeof(Uniforms)
                                            options:MTLResourceStorageModeShared];
        if (!_uniformBuffer) {
            NSLog(@"Failed to create uniform buffer");
        }
    }
}

- (void)updateViewportWidth:(int)width height:(int)height {
    _viewportSize = (vector_uint2){width, height};
    [self updateMVPMatrix];
}

- (void)setCameraRotation:(float)roll pitch:(float)pitch yaw:(float)yaw {
    _roll = roll;
    _pitch = pitch;
    _yaw = yaw;
    [self updateMVPMatrix];
}

- (void)updateMVPMatrix {
    if (_viewportSize.x == 0 || _viewportSize.y == 0) return;
    
    float aspect = (float)_viewportSize.x / (float)_viewportSize.y;
    float fov = FIELD_OF_VIEW * (M_PI / 180.0f);
    
    matrix_float4x4 perspective = matrix4x4_perspective(fov, aspect, 0.1f, 100.0f);
    matrix_float4x4 modelView = matrix4x4_identity();
    
    modelView = matrix4x4_rotation(modelView, -_pitch, (vector_float3){1, 0, 0});
    modelView = matrix4x4_rotation(modelView, -_yaw, (vector_float3){0, 1, 0});
    modelView = matrix4x4_rotation(modelView, -_roll, (vector_float3){0, 0, 1});
    
    if (!_uniformBuffer) {
        NSLog(@"Uniform buffer is nil during MVP update");
        return;
    }
    
    void *contents = [_uniformBuffer contents];
    if (!contents) {
        NSLog(@"Failed to get uniform buffer contents");
        return;
    }
    
    Uniforms uniforms;
    uniforms.modelViewProjectionMatrix = matrix_multiply(perspective, modelView);
    
    memcpy(contents, &uniforms, sizeof(Uniforms));
}

- (void)drawWithCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
                     texture:(id<MTLTexture>)texture
                     inView:(MTKView *)view {
    if (!_mesh || !_pipelineState || !commandBuffer || !texture || !view) return;
    
    MTLRenderPassDescriptor *renderPassDescriptor = view.currentRenderPassDescriptor;
    if (!renderPassDescriptor) return;
    
    id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
    if (!renderEncoder) return;
    
    [renderEncoder setRenderPipelineState:_pipelineState];
    
    // Verify vertex buffer exists before setting it
    if (!_vertexBuffer) {
        [renderEncoder endEncoding];
        return;
    }
    [renderEncoder setVertexBuffer:_vertexBuffer offset:0 atIndex:0];
    
    // Verify uniform buffer exists before setting it
    if (!_uniformBuffer) {
        [renderEncoder endEncoding];
        return;
    }
    [renderEncoder setVertexBuffer:_uniformBuffer offset:0 atIndex:1];
    
    [renderEncoder setFragmentTexture:texture atIndex:0];
    
    if (_indexBuffer && _indexCount > 0) {
        [renderEncoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                                indexCount:_indexCount
                                 indexType:MTLIndexTypeUInt16
                               indexBuffer:_indexBuffer
                         indexBufferOffset:0];
    } else if (_vertexCount > 0) {
        [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle
                        vertexStart:0
                        vertexCount:_vertexCount];
    }
    
    [renderEncoder endEncoding];
}

- (void)updateTexture:(CVPixelBufferRef)pixelBuffer {
    if (!pixelBuffer || !_textureCache) return;
    
    CVMetalTextureCacheFlush(_textureCache, 0);
}

- (void)shutdown {
    // First release all Metal resources
    _vertexBuffer = nil;
    _indexBuffer = nil;
    _uniformBuffer = nil;
    _pipelineState = nil;
    
    if (_textureCache) {
        CFRelease(_textureCache);
        _textureCache = NULL;
    }
}

- (void)dealloc {
    [self shutdown];
}

#pragma mark - Helper Functions

static matrix_float4x4 matrix4x4_perspective(float fovy, float aspect, float near, float far) {
    float yScale = 1.0f / tanf(fovy * 0.5f);
    float xScale = yScale / aspect;
    float zRange = far - near;
    float zScale = -(far + near) / zRange;
    float wzScale = -2.0f * far * near / zRange;
    
    vector_float4 P0 = {xScale, 0, 0, 0};
    vector_float4 P1 = {0, yScale, 0, 0};
    vector_float4 P2 = {0, 0, zScale, -1};
    vector_float4 P3 = {0, 0, wzScale, 0};
    
    matrix_float4x4 m = {P0, P1, P2, P3};
    return m;
}

static matrix_float4x4 matrix4x4_rotation(matrix_float4x4 matrix, float angle, vector_float3 axis) {
    float c = cosf(angle);
    float s = sinf(angle);
    float t = 1.0f - c;
    
    vector_float3 norm_axis = vector_normalize(axis);
    float x = norm_axis.x;
    float y = norm_axis.y;
    float z = norm_axis.z;
    
    matrix_float4x4 rot = {
        {t*x*x + c, t*x*y + z*s, t*x*z - y*s, 0},
        {t*x*y - z*s, t*y*y + c, t*y*z + x*s, 0},
        {t*x*z + y*s, t*y*z - x*s, t*z*z + c, 0},
        {0, 0, 0, 1}
    };
    
    return matrix_multiply(matrix, rot);
}

static matrix_float4x4 matrix4x4_identity(void) {
    return (matrix_float4x4) {
        {1, 0, 0, 0},
        {0, 1, 0, 0},
        {0, 0, 1, 0},
        {0, 0, 0, 1}
    };
}

@end 
