//
//  Video360Renderer.m
//  video_player
//
//  Created by Eittipat K on 20/1/2565 BE.
//  Modified to silence OpenGL ES deprecation warnings in iOS 12+
//

#import "Video360Renderer.h"
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <simd/simd.h>

#define FIELD_OF_VIEW 90

// Metal shader source code
static NSString *const shaderSource = @"#include <metal_stdlib>\n"
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
                            "vertex VertexOut vertex_main(const device VertexIn* vertices [[buffer(0)]],\n"
                            "                            constant Uniforms &uniforms [[buffer(1)]],\n"
                            "                            uint vid [[vertex_id]]) {\n"
                            "    VertexOut out;\n"
                            "    VertexIn in = vertices[vid];\n"
                            "    out.position = uniforms.modelViewProjectionMatrix * float4(in.position, 1.0);\n"
                            "    out.texCoord = in.texCoord;\n"
                            "    return out;\n"
                            "}\n"
                            "\n"
                            "fragment float4 fragment_main(VertexOut in [[stage_in]],\n"
                            "                             texture2d<float> tex [[texture(0)]],\n"
                            "                             sampler textureSampler [[sampler(0)]]) {\n"
                            "    float2 tex_size = float2(tex.get_width(), tex.get_height());\n"
                            "    float2 tex_pixel = 1.0 / tex_size;\n"
                            "    \n"
                            "    // Sample center and neighbors\n"
                            "    float4 center = tex.sample(textureSampler, in.texCoord);\n"
                            "    float4 top = tex.sample(textureSampler, in.texCoord + float2(0, -tex_pixel.y));\n"
                            "    float4 bottom = tex.sample(textureSampler, in.texCoord + float2(0, tex_pixel.y));\n"
                            "    float4 left = tex.sample(textureSampler, in.texCoord + float2(-tex_pixel.x, 0));\n"
                            "    float4 right = tex.sample(textureSampler, in.texCoord + float2(tex_pixel.x, 0));\n"
                            "    \n"
                            "    // Very subtle sharpening\n"
                            "    float sharpenStrength = 0.5;\n"
                            "    float4 sharpened = center * (1.0 + 4.0 * sharpenStrength) -\n"
                            "                       (top + bottom + left + right) * sharpenStrength;\n"
                            "    \n"
                            "    return sharpened;\n"
                            "}";

// Vertex structure
typedef struct {
    vector_float3 position;
    vector_float2 texCoord;
} Vertex;

// Uniforms structure that will be passed to the shader
typedef struct {
    matrix_float4x4 modelViewProjectionMatrix;
} Uniforms;

@interface Video360Renderer ()
@property (nonatomic, strong) id<MTLDevice> device;
@property (nonatomic, strong) id<MTLCommandQueue> commandQueue;
@property (nonatomic, strong) id<MTLRenderPipelineState> pipelineState;
@property (nonatomic, strong) id<MTLBuffer> vertexBuffer;
@property (nonatomic, strong) id<MTLBuffer> indexBuffer;
@property (nonatomic, strong) id<MTLBuffer> uniformBuffer;
@property (nonatomic, strong) id<MTLTexture> texture;
@property (nonatomic, strong) id<MTLSamplerState> samplerState;
@end

@implementation Video360Renderer {
    Mesh *_requestedDisplayMesh;
    Mesh *_displayMesh;
    matrix_float4x4 _mvpMatrix;
    
    float _roll;
    float _pitch;
    float _yaw;
}

// Forward declarations of helper functions
static matrix_float4x4 matrix4x4_identity(void);
static matrix_float4x4 matrix4x4_perspective(float fovRadians, float aspect, float nearZ, float farZ);
static matrix_float4x4 matrix4x4_rotation(float radians, vector_float3 axis);

- (instancetype)init {
    @try {
        self = [super init];
        if (self) {
            _device = MTLCreateSystemDefaultDevice();
            if (!_device) {
                NSLog(@"Warning: Failed to create Metal device, will try again later");
                return self;
            }
            
            _commandQueue = [_device newCommandQueue];
            if (!_commandQueue) {
                NSLog(@"Warning: Failed to create command queue, will try again later");
                return self;
            }
            
            if (![self setupMetal]) {
                NSLog(@"Warning: Failed to setup Metal, will try again later");
            }
            
            _mvpMatrix = matrix4x4_identity();
            _roll = 0.0f;
            _pitch = 0.0f;
            _yaw = 0.0f;
        }
        return self;
    } @catch (NSException *exception) {
        NSLog(@"Warning: Exception during initialization: %@", exception);
        return self;
    }
}

- (BOOL)setupMetal {
    @try {
        if (!self.device) {
            NSLog(@"Error: Metal device is nil during setup");
            return NO;
        }

        if (!self.commandQueue) {
            NSLog(@"Error: Command queue is nil during setup");
            return NO;
        }

        @autoreleasepool {
            NSError *error = nil;
            
            // Create shader library with optimization options
            MTLCompileOptions *options = [[MTLCompileOptions alloc] init];
            options.optimizationLevel = MTLLibraryOptimizationLevelDefault;
            
            id<MTLLibrary> library = [self.device newLibraryWithSource:shaderSource options:options error:&error];
            if (!library) {
                NSLog(@"Error: Failed to create shader library: %@", error.localizedDescription);
                if (error.userInfo[@"NSMetalCompileOptions"]) {
                    NSLog(@"Compile options: %@", error.userInfo[@"NSMetalCompileOptions"]);
                }
                if (error.userInfo[@"NSMetalErrorMessages"]) {
                    NSLog(@"Shader errors:\n%@", [error.userInfo[@"NSMetalErrorMessages"] componentsJoinedByString:@"\n"]);
                }
                return NO;
            }
            
            // Get shader functions
            id<MTLFunction> vertexFunction = [library newFunctionWithName:@"vertex_main"];
            id<MTLFunction> fragmentFunction = [library newFunctionWithName:@"fragment_main"];
            
            if (!vertexFunction || !fragmentFunction) {
                NSLog(@"Warning: Failed to create shader functions");
                return NO;
            }
            
            // Create pipeline state with error recovery
            if (![self createPipelineStateWithVertex:vertexFunction fragment:fragmentFunction]) {
                NSLog(@"Warning: Failed to create pipeline state");
                return NO;
            }
            
            return YES;
        }
    } @catch (NSException *exception) {
        NSLog(@"Warning: Exception during Metal setup: %@", exception);
        return NO;
    }
}

- (BOOL)createPipelineStateWithVertex:(id<MTLFunction>)vertexFunction fragment:(id<MTLFunction>)fragmentFunction {
    @try {
        // Add validation for input parameters
        if (!vertexFunction || !fragmentFunction) {
            NSLog(@"Error: Invalid shader functions provided to pipeline creation");
            return NO;
        }

        if (!self.device) {
            NSLog(@"Error: Metal device is nil during pipeline creation");
            return NO;
        }

        // Create vertex descriptor
        MTLVertexDescriptor *vertexDescriptor = [[MTLVertexDescriptor alloc] init];
        
        // Position attribute
        vertexDescriptor.attributes[0].format = MTLVertexFormatFloat3;
        vertexDescriptor.attributes[0].offset = offsetof(Vertex, position);
        vertexDescriptor.attributes[0].bufferIndex = 0;
        
        // Texture coordinate attribute
        vertexDescriptor.attributes[1].format = MTLVertexFormatFloat2;
        vertexDescriptor.attributes[1].offset = offsetof(Vertex, texCoord);
        vertexDescriptor.attributes[1].bufferIndex = 0;
        
        // Layout
        vertexDescriptor.layouts[0].stride = sizeof(Vertex);
        vertexDescriptor.layouts[0].stepRate = 1;
        vertexDescriptor.layouts[0].stepFunction = MTLVertexStepFunctionPerVertex;
        
        // Create pipeline descriptor
        MTLRenderPipelineDescriptor *pipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
        pipelineDescriptor.label = @"360 Video Pipeline";
        pipelineDescriptor.vertexFunction = vertexFunction;
        pipelineDescriptor.fragmentFunction = fragmentFunction;
        pipelineDescriptor.vertexDescriptor = vertexDescriptor;
        pipelineDescriptor.rasterSampleCount = 1;
        
        // Configure color attachment with safe defaults
        pipelineDescriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
        pipelineDescriptor.colorAttachments[0].blendingEnabled = YES;
        pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
        pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
        pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;
        pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
        
        // Create pipeline state with error handling
        NSError *error = nil;
        id<MTLRenderPipelineState> newPipelineState = [self.device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:&error];
        if (!newPipelineState) {
            NSLog(@"Error: Failed to create pipeline state: %@", error);
            return NO;
        }
        
        // Create sampler state with error recovery
        if (![self createSamplerState]) {
            return NO;
        }
        
        // Create uniform buffer with error recovery
        if (![self createUniformBuffer]) {
            return NO;
        }
        
        // Only assign to instance variable after successful creation
        _pipelineState = newPipelineState;
        
        return YES;
    } @catch (NSException *exception) {
        NSLog(@"Warning: Exception during pipeline state creation: %@", exception);
        return NO;
    }
}

- (BOOL)createSamplerState {
    @try {
        MTLSamplerDescriptor *samplerDescriptor = [[MTLSamplerDescriptor alloc] init];
        samplerDescriptor.minFilter = MTLSamplerMinMagFilterLinear;
        samplerDescriptor.magFilter = MTLSamplerMinMagFilterLinear;
        samplerDescriptor.mipFilter = MTLSamplerMipFilterLinear;
        samplerDescriptor.maxAnisotropy = 16;
        samplerDescriptor.sAddressMode = MTLSamplerAddressModeClampToEdge;
        samplerDescriptor.tAddressMode = MTLSamplerAddressModeClampToEdge;
        samplerDescriptor.supportArgumentBuffers = YES;
        
        _samplerState = [_device newSamplerStateWithDescriptor:samplerDescriptor];
        if (!_samplerState) {
            NSLog(@"Warning: Failed to create sampler state");
            return NO;
        }
        return YES;
    } @catch (NSException *exception) {
        NSLog(@"Warning: Exception during sampler state creation: %@", exception);
        return NO;
    }
}

- (BOOL)createUniformBuffer {
    @try {
        _uniformBuffer = [self.device newBufferWithLength:sizeof(Uniforms)
                                                options:MTLResourceStorageModeShared | MTLResourceCPUCacheModeWriteCombined];
        if (!_uniformBuffer) {
            NSLog(@"Warning: Failed to create uniform buffer");
            return NO;
        }
        return YES;
    } @catch (NSException *exception) {
        NSLog(@"Warning: Exception during uniform buffer creation: %@", exception);
        return NO;
    }
}

- (void)configureSurface:(Mesh *)mesh {
    _requestedDisplayMesh = mesh;
    [self updateMeshBuffers];
}

- (void)updateMeshBuffers {
    @try {
        if (!_requestedDisplayMesh) return;
        
        // Get mesh data with error handling
        float *vertices = NULL;
        uint16_t *indices = NULL;
        NSUInteger vertexCount = 0, indexCount = 0;
        
        @try {
            [_requestedDisplayMesh getVertices:&vertices count:&vertexCount];
            [_requestedDisplayMesh getIndices:&indices count:&indexCount];
        } @catch (NSException *exception) {
            NSLog(@"Warning: Exception getting mesh data: %@", exception);
            if (vertices) free(vertices);
            if (indices) free(indices);
            return;
        }
        
        // Validate input data
        if (!vertices || vertexCount == 0) {
            NSLog(@"Warning: Invalid vertex data");
            if (indices) free(indices);
            return;
        }
        
        // Calculate vertex buffer size
        NSUInteger actualVertexCount = vertexCount / 5;
        NSUInteger bufferLength = actualVertexCount * sizeof(Vertex);
        
        // Create vertex data with error handling
        Vertex *vertexData = (Vertex *)calloc(actualVertexCount, sizeof(Vertex));
        if (!vertexData) {
            NSLog(@"Warning: Failed to allocate vertex data");
            free(vertices);
            if (indices) free(indices);
            return;
        }
        
        // Convert vertices to Metal format
        for (NSUInteger i = 0; i < actualVertexCount; i++) {
            NSUInteger srcIdx = i * 5;
            vertexData[i].position = (vector_float3){
                -vertices[srcIdx],
                vertices[srcIdx + 1],
                vertices[srcIdx + 2]
            };
            vertexData[i].texCoord = (vector_float2){
                1.0 - vertices[srcIdx + 3],
                vertices[srcIdx + 4]
            };
        }
        
        // Create vertex buffer with error handling
        id<MTLBuffer> newVertexBuffer = [self.device newBufferWithBytes:vertexData
                                                               length:bufferLength
                                                              options:MTLResourceStorageModeShared];
        free(vertexData);
        free(vertices);
        
        if (!newVertexBuffer) {
            NSLog(@"Warning: Failed to create vertex buffer");
            if (indices) free(indices);
            return;
        }
        
        // Create index buffer if indices are present
        id<MTLBuffer> newIndexBuffer = nil;
        if (indices && indexCount > 0) {
            newIndexBuffer = [self.device newBufferWithBytes:indices
                                                    length:indexCount * sizeof(uint16_t)
                                                   options:MTLResourceStorageModeShared];
            free(indices);
            
            if (!newIndexBuffer) {
                NSLog(@"Warning: Failed to create index buffer");
                return;
            }
        }
        
        // Update instance variables only after successful creation
        _vertexBuffer = newVertexBuffer;
        _indexBuffer = newIndexBuffer;
        _displayMesh = _requestedDisplayMesh;
        _requestedDisplayMesh = nil;
        
    } @catch (NSException *exception) {
        NSLog(@"Warning: Exception during mesh buffer update: %@", exception);
    }
}

- (void)onDrawFrame:(id<MTLTexture>)renderTarget {
    @try {
        // Add explicit validation of all required resources
        if (!self.device || !self.commandQueue || !_pipelineState) {
            NSLog(@"Warning: Required Metal resources are nil, skipping frame");
            return;
        }

        if (!_displayMesh || !renderTarget || !_texture || !_vertexBuffer) {
            // Log more specific debug info
            NSLog(@"Warning: Required rendering resources are nil - displayMesh: %@, renderTarget: %@, texture: %@, vertexBuffer: %@",
                  _displayMesh ? @"valid" : @"nil",
                  renderTarget ? @"valid" : @"nil",
                  _texture ? @"valid" : @"nil",
                  _vertexBuffer ? @"valid" : @"nil");
            return;
        }

        // Create command buffer first to validate pipeline is still valid
        id<MTLCommandBuffer> commandBuffer = [self.commandQueue commandBuffer];
        if (!commandBuffer) {
            NSLog(@"Warning: Failed to create command buffer");
            return;
        }

        [self computePerspective];
        
        // Update uniforms with error handling
        @try {
            Uniforms uniforms;
            uniforms.modelViewProjectionMatrix = _mvpMatrix;
            void *contents = [_uniformBuffer contents];
            if (contents) {
                memcpy(contents, &uniforms, sizeof(Uniforms));
            }
        } @catch (NSException *exception) {
            NSLog(@"Warning: Exception updating uniforms: %@", exception);
            return;
        }
        
        MTLRenderPassDescriptor *renderPassDescriptor = [MTLRenderPassDescriptor renderPassDescriptor];
        renderPassDescriptor.colorAttachments[0].texture = renderTarget;
        renderPassDescriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
        renderPassDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1);
        
        id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
        if (!renderEncoder) {
            return;
        }
        
        @try {
            [renderEncoder setRenderPipelineState:_pipelineState];
            [renderEncoder setVertexBuffer:_vertexBuffer offset:0 atIndex:0];
            [renderEncoder setVertexBuffer:_uniformBuffer offset:0 atIndex:1];
            [renderEncoder setFragmentTexture:_texture atIndex:0];
            [renderEncoder setFragmentSamplerState:_samplerState atIndex:0];
            
            NSUInteger indexCount = [_displayMesh indexCount];
            if (_indexBuffer && indexCount > 0) {
                [renderEncoder drawIndexedPrimitives:MTLPrimitiveTypeTriangleStrip
                                        indexCount:indexCount
                                         indexType:MTLIndexTypeUInt16
                                       indexBuffer:_indexBuffer
                                 indexBufferOffset:0];
            } else {
                // Get vertex count safely
                float *vertices = NULL;
                NSUInteger totalVertexCount = 0;
                @try {
                    [_displayMesh getVertices:&vertices count:&totalVertexCount];
                    if (vertices) {
                        free(vertices);
                        vertices = NULL;
                    }
                } @catch (NSException *exception) {
                    NSLog(@"Warning: Failed to get vertex count: %@", exception);
                    if (vertices) {
                        free(vertices);
                    }
                    return;
                }
                
                // Calculate actual vertex count (total floats / floats per vertex)
                NSUInteger actualVertexCount = totalVertexCount / 5; // 3 for position + 2 for texcoord
                
                // Validate vertex count
                if (actualVertexCount == 0) {
                    NSLog(@"Warning: Invalid vertex count");
                    return;
                }
                
                // Draw with validated vertex count
                [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangleStrip
                                vertexStart:0
                                vertexCount:actualVertexCount];
            }
            
            [renderEncoder endEncoding];
            [commandBuffer commit];
            
            // Add completion handler to catch any errors
            [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> buffer) {
                if (buffer.error) {
                    NSLog(@"Command buffer error: %@", buffer.error);
                }
            }];
            
        } @catch (NSException *exception) {
            NSLog(@"Warning: Exception during rendering: %@", exception);
        }
    } @catch (NSException *exception) {
        NSLog(@"Warning: Exception in draw frame: %@", exception);
    }
}

- (void)onSurfaceChanged:(int)width :(int)height {
    float aspect = (float)width / (float)height;
    [self computePerspective];
}

- (void)onSurfaceCreated {
    // Metal initialization is handled in init and setupMetal
}

- (void)setCameraRotation:(float)roll :(float)pitch :(float)yaw {
    _roll = roll;
    _pitch = pitch;
    _yaw = yaw;
}

- (void)updateTexture:(CVPixelBufferRef)pixelBuffer {
    @try {
        if (!pixelBuffer) return;
        
        @autoreleasepool {
            _texture = nil;
            
            static CVMetalTextureCacheRef textureCache = NULL;
            if (!textureCache) {
                CVReturn result = CVMetalTextureCacheCreate(kCFAllocatorDefault,
                                                          NULL,
                                                          self.device,
                                                          NULL,
                                                          &textureCache);
                if (result != kCVReturnSuccess) {
                    NSLog(@"Warning: Failed to create texture cache");
                    return;
                }
            }
            
            CVPixelBufferLockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
            
            @try {
                size_t width = CVPixelBufferGetWidth(pixelBuffer);
                size_t height = CVPixelBufferGetHeight(pixelBuffer);
                
                CVMetalTextureRef metalTextureRef = NULL;
                CVReturn result = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                                          textureCache,
                                                                          pixelBuffer,
                                                                          NULL,
                                                                          MTLPixelFormatBGRA8Unorm,
                                                                          width,
                                                                          height,
                                                                          0,
                                                                          &metalTextureRef);
                
                if (result == kCVReturnSuccess && metalTextureRef) {
                    _texture = CVMetalTextureGetTexture(metalTextureRef);
                    CFRelease(metalTextureRef);
                }
            } @finally {
                CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
            }
        }
    } @catch (NSException *exception) {
        NSLog(@"Warning: Exception updating texture: %@", exception);
    }
}

- (void)computePerspective {
    // Reuse matrices to avoid allocations
    static matrix_float4x4 projectionMatrix, viewMatrix, rotationMatrix;
    
    float aspect = 1.0f;
    float fovRadians = FIELD_OF_VIEW * M_PI / 180.0f;
    
    projectionMatrix = matrix4x4_perspective(fovRadians, aspect, 0.1f, 100.0f);
    viewMatrix = matrix4x4_identity();
    rotationMatrix = matrix4x4_identity();
    
    // Optimize rotation calculations
    if (_yaw != 0.0f) {
        rotationMatrix = matrix_multiply(matrix4x4_rotation(_yaw * M_PI / 180.0f, (vector_float3){0, 1, 0}), rotationMatrix);
    }
    if (_pitch != 0.0f) {
        rotationMatrix = matrix_multiply(matrix4x4_rotation(_pitch * M_PI / 180.0f, (vector_float3){1, 0, 0}), rotationMatrix);
    }
    if (_roll != 0.0f) {
        rotationMatrix = matrix_multiply(matrix4x4_rotation(_roll * M_PI / 180.0f, (vector_float3){0, 0, 1}), rotationMatrix);
    }
    
    viewMatrix.columns[3].z = -2.0f;
    
    matrix_float4x4 modelViewMatrix = matrix_multiply(viewMatrix, rotationMatrix);
    _mvpMatrix = matrix_multiply(projectionMatrix, modelViewMatrix);
}

// Helper functions for matrix operations
static matrix_float4x4 matrix4x4_identity(void) {
    return matrix_identity_float4x4;
}

static matrix_float4x4 matrix4x4_perspective(float fovRadians, float aspect, float nearZ, float farZ) {
    float ys = 1 / tanf(fovRadians * 0.5);
    float xs = ys / aspect;
    float zs = farZ / (nearZ - farZ);
    
    return (matrix_float4x4) {{
        { xs,  0,  0,  0 },
        { 0, ys,  0,  0 },
        { 0,  0, zs, -1 },
        { 0,  0, zs * nearZ,  0 }
    }};
}

static matrix_float4x4 matrix4x4_rotation(float radians, vector_float3 axis) {
    axis = vector_normalize(axis);
    float ct = cosf(radians);
    float st = sinf(radians);
    float ci = 1 - ct;
    float x = axis.x, y = axis.y, z = axis.z;
    
    return (matrix_float4x4) {{
        { ct + x * x * ci,     y * x * ci + z * st, z * x * ci - y * st, 0 },
        { x * y * ci - z * st,     ct + y * y * ci, z * y * ci + x * st, 0 },
        { x * z * ci + y * st, y * z * ci - x * st,     ct + z * z * ci, 0 },
        { 0, 0, 0, 1 }
    }};
}

- (void)glShutdown {
    @try {
        @autoreleasepool {
            // Check if we're on the main thread
            if ([NSThread isMainThread]) {
                // We're already on main thread, just clean up directly
                [self cleanupResources];
            } else {
                // We're on a background thread, dispatch to main thread
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self cleanupResources];
                });
            }
        }
    } @catch (NSException *exception) {
        NSLog(@"Warning: Exception during shutdown: %@", exception);
    }
}

- (void)cleanupResources {
    // First invalidate command queue to prevent new commands
    _commandQueue = nil;
    
    // Clear render resources in reverse creation order
    _pipelineState = nil;
    _samplerState = nil;
    _texture = nil;
    _indexBuffer = nil;
    _vertexBuffer = nil;
    _uniformBuffer = nil;
    
    // Clear mesh data
    _displayMesh = nil;
    _requestedDisplayMesh = nil;
    
    // Finally clear the device
    _device = nil;
    
    // Metal will automatically manage resources when we nil the references
    // No need for explicit heap management since we're not using MTLHeaps
}

// Update dealloc to ensure we're not causing deadlocks
- (void)dealloc {
    // If we're on main thread, clean up directly
    if ([NSThread isMainThread]) {
        [self cleanupResources];
    } else {
        // If we're on background thread, dispatch async to main
        dispatch_async(dispatch_get_main_queue(), ^{
            [self cleanupResources];
        });
    }
}

@end
