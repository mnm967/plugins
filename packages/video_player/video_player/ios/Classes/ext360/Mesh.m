//
//  Mesh.m
//  video_player
//
//  Created by Eittipat K on 20/1/2565 BE.
//

#import "Mesh.h"
#import "Utils.h"
@import Metal;
@import MetalKit;
@import simd;

#define SPHERE_POSITION_COORDS_PER_VERTEX 3
#define SPHERE_TEXTURE_COORDS_PER_VERTEX 2
#define SPHERE_CPV 5
#define SPHERE_VERTEX_STRIDE_BYTES (SPHERE_CPV * sizeof(float))

#define CANVAS_QUAD_POSITION_COORDS_PER_VERTEX 3
#define CANVAS_QUAD_TEXTURE_COORDS_PER_VERTEX 2
#define CANVAS_QUAD_CPV 5
#define CANVAS_QUAD_VERTEX_STRIDE_BYTES (CANVAS_QUAD_CPV * sizeof(float))

#define MEDIA_MONOSCOPIC 0
#define MEDIA_STEREO_LEFT_RIGHT 1
#define MEDIA_STEREO_TOP_BOTTOM 2

const NSString* SPHERE_VERTEX_SHADER_CODE =
@"#version 300 es\n"\
@"uniform mat4 uMvpMatrix;\n"\
@"in vec4 aPosition;\n"\
@"in vec2 aTexCoords;\n"\
@"out vec2 vTexCoords;\n"\
@"void main() {\n"\
@"  gl_Position = uMvpMatrix * aPosition;\n"\
@"  vTexCoords = vec2(aTexCoords.x, 1.0 - aTexCoords.y);\n"\
@"}";

const NSString* CANVAS_QUAD_VERTEX_SHADER_CODE =
@"#version 300 es\n"\
@"in vec4 aPosition;\n"\
@"in vec2 aTexCoords;\n"\
@"out vec2 vTexCoords;\n"\
@"void main() {\n"\
@"  gl_Position = aPosition;\n"\
@"  vTexCoords = vec2(aTexCoords.x, 1.0 - aTexCoords.y);\n"\
@"}";

const NSString* FRAGMENT_SHADER_CODE =
@"#version 300 es\n"\
@"precision mediump float;\n"\
@"uniform sampler2D uTexture;\n"\
@"in vec2 vTexCoords;\n"\
@"out vec4 fragmentColor;\n"\
@"void main() {\n"\
@"  fragmentColor = texture(uTexture, vTexCoords);\n"\
@"}";

@implementation Mesh {
@protected
    id<MTLDevice> _device;
    id<MTLBuffer> _vertexBuffer;
    id<MTLBuffer> _indexBuffer;
}

- (instancetype)initWithVertices:(float*)vertices length:(NSUInteger)length {
    self = [super init];
    if (self) {
        _length = length;
        [self setVertices:vertices count:length];
        _device = MTLCreateSystemDefaultDevice();
    }
    return self;
}

- (void)getVertices:(float **)vertices count:(NSUInteger *)count {
    if (_vertices && _vertexCount > 0) {
        *vertices = (float *)malloc(_vertexCount * sizeof(float));
        if (*vertices) {
            memcpy(*vertices, _vertices, _vertexCount * sizeof(float));
            *count = _vertexCount;
        } else {
            *vertices = NULL;
            *count = 0;
        }
    } else {
        *vertices = NULL;
        *count = 0;
    }
}

- (void)getIndices:(uint16_t **)indices count:(NSUInteger *)count {
    if (_indices && _indexCount > 0) {
        *indices = (uint16_t *)malloc(_indexCount * sizeof(uint16_t));
        if (*indices) {
            memcpy(*indices, _indices, _indexCount * sizeof(uint16_t));
            *count = _indexCount;
        } else {
            *indices = NULL;
            *count = 0;
        }
    } else {
        *indices = NULL;
        *count = 0;
    }
}

- (void)setVertices:(float *)vertices count:(NSUInteger)count {
    if (_vertices) {
        free(_vertices);
        _vertices = NULL;
    }
    if (vertices && count > 0) {
        _vertices = (float *)malloc(count * sizeof(float));
        if (_vertices) {
            memcpy(_vertices, vertices, count * sizeof(float));
            _vertexCount = count;
            
            // Create Metal vertex buffer
            if (_device) {
                _vertexBuffer = [_device newBufferWithBytes:_vertices
                                                   length:count * sizeof(float)
                                                  options:MTLResourceStorageModeShared];
            }
        } else {
            _vertexCount = 0;
        }
    } else {
        _vertices = NULL;
        _vertexCount = 0;
    }
}

- (void)setIndices:(uint16_t *)indices count:(NSUInteger)count {
    if (_indices) {
        free(_indices);
        _indices = NULL;
    }
    if (indices && count > 0) {
        _indices = (uint16_t *)malloc(count * sizeof(uint16_t));
        if (_indices) {
            memcpy(_indices, indices, count * sizeof(uint16_t));
            _indexCount = count;
            
            // Create Metal index buffer
            if (_device) {
                _indexBuffer = [_device newBufferWithBytes:_indices
                                                  length:count * sizeof(uint16_t)
                                                 options:MTLResourceStorageModeShared];
            }
        } else {
            _indexCount = 0;
        }
    } else {
        _indices = NULL;
        _indexCount = 0;
    }
}

- (NSUInteger)indexCount {
    return _indexCount;
}

- (void)dealloc {
    if (_vertices) {
        free(_vertices);
        _vertices = NULL;
    }
    if (_indices) {
        free(_indices);
        _indices = NULL;
    }
    _vertexBuffer = nil;
    _indexBuffer = nil;
    _device = nil;
}

@end

@implementation Sphere

+(instancetype)createUvSphereWithRadius:(float)radius
                              latitudes:(int)latitudes
                             longitudes:(int)longitudes
                     verticalFovDegrees:(float)verticalFovDegrees
                   horizontalFovDegrees:(float)horizontalFovDegrees
                            mediaFormat:(int)mediaFormat {
    
    if (radius <= 0
        || latitudes < 1 || longitudes < 1
        || verticalFovDegrees <= 0 || verticalFovDegrees > 180
        || horizontalFovDegrees <= 0 || horizontalFovDegrees > 360) {
        NSLog(@"Invalid Parameters");
        return nil;
    }
    
    // Pre-calculate trig values
    float verticalFovRads = GLKMathDegreesToRadians(verticalFovDegrees);
    float horizontalFovRads = GLKMathDegreesToRadians(horizontalFovDegrees);
    float quadHeightRads = verticalFovRads / (float)latitudes;
    float quadWidthRads = horizontalFovRads / (float)longitudes;
    
    const int CPV = SPHERE_CPV;
    int vertexCount = (2 * (longitudes + 1) + 2) * latitudes;
    int length = vertexCount * CPV;
    
    // Allocate vertex buffer
    float *vertexData = (float*)calloc(length, sizeof(float));
    if (!vertexData) {
        NSLog(@"Failed to allocate vertex data");
        return nil;
    }
    
    // Cache sin/cos values
    float *sinTheta = (float*)malloc((longitudes + 1) * sizeof(float));
    float *cosTheta = (float*)malloc((longitudes + 1) * sizeof(float));
    float *sinPhi = (float*)malloc(2 * sizeof(float));
    float *cosPhi = (float*)malloc(2 * sizeof(float));
    
    if (!sinTheta || !cosTheta || !sinPhi || !cosPhi) {
        free(vertexData);
        free(sinTheta);
        free(cosTheta);
        free(sinPhi);
        free(cosPhi);
        return nil;
    }
    
    // Pre-calculate theta values
    for (int i = 0; i <= longitudes; i++) {
        float theta = quadWidthRads * i + (float)M_PI - horizontalFovRads / 2;
        sinTheta[i] = sin(theta);
        cosTheta[i] = cos(theta);
    }
    
    int v = 0;
    for (int j = 0; j < latitudes; ++j) {
        float phiLow = (quadHeightRads * j - verticalFovRads / 2);
        float phiHigh = (quadHeightRads * (j + 1) - verticalFovRads / 2);
        
        sinPhi[0] = sin(phiLow);
        cosPhi[0] = cos(phiLow);
        sinPhi[1] = sin(phiHigh);
        cosPhi[1] = cos(phiHigh);
        
        for (int i = 0; i <= longitudes; ++i) {
            for (int k = 0; k < 2; ++k) {
                // Position
                vertexData[CPV * v + 0] = -(float)(radius * sinTheta[i] * cosPhi[k]);
                vertexData[CPV * v + 1] = (float)(radius * sinPhi[k]);
                vertexData[CPV * v + 2] = (float)(radius * cosTheta[i] * cosPhi[k]);
                
                // Texture coordinates
                float u = (float)i / longitudes;
                float v_tex = 1.0f - ((float)(j + k) / latitudes);
                
                if (mediaFormat == MEDIA_STEREO_LEFT_RIGHT) {
                    u *= 0.5f;
                } else if (mediaFormat == MEDIA_STEREO_TOP_BOTTOM) {
                    v_tex = v_tex * 0.5f + 0.5f;
                }
                
                vertexData[CPV * v + 3] = u;
                vertexData[CPV * v + 4] = v_tex;
                
                v++;
                
                if ((i == 0 && k == 0) || (i == longitudes && k == 1)) {
                    memcpy(&vertexData[CPV * v], &vertexData[CPV * (v-1)], CPV * sizeof(float));
                    v++;
                }
            }
        }
    }
    
    free(sinTheta);
    free(cosTheta);
    free(sinPhi);
    free(cosPhi);
    
    // Create indices for triangle strip
    uint16_t* indices = (uint16_t*)malloc(vertexCount * sizeof(uint16_t));
    if (!indices) {
        free(vertexData);
        return nil;
    }
    
    for (int i = 0; i < vertexCount; i++) {
        indices[i] = i;
    }
    
    Sphere* sphere = [[self alloc] initWithVertices:vertexData length:length];
    [sphere setVertices:vertexData count:length];
    [sphere setIndices:indices count:vertexCount];
    
    free(vertexData);
    free(indices);
    
    return sphere;
}

@end

@implementation CanvasQuad

+(instancetype)createCanvasQuad {
    // Define vertices with positions and texture coordinates
    float vertices[] = {
        // positions (x, y, z)    // texture coords (u, v)
        -1.0f, -1.0f, 0.0f,      0.0f, 1.0f,    // bottom left
         1.0f, -1.0f, 0.0f,      1.0f, 1.0f,    // bottom right
        -1.0f,  1.0f, 0.0f,      0.0f, 0.0f,    // top left
         1.0f,  1.0f, 0.0f,      1.0f, 0.0f     // top right
    };
    
    // Create a copy of vertices
    NSUInteger vertexDataSize = 20 * sizeof(float); // 4 vertices * 5 components
    float *vertexData = (float *)malloc(vertexDataSize);
    memcpy(vertexData, vertices, vertexDataSize);
    
    // Create the quad instance
    CanvasQuad *quad = [[CanvasQuad alloc] initWithVertices:vertexData length:20];
    
    // Define and set indices for triangle strip
    uint16_t indices[] = {0, 1, 2, 3}; // Triangle strip order
    NSUInteger indexDataSize = 4 * sizeof(uint16_t);
    uint16_t *indexData = (uint16_t *)malloc(indexDataSize);
    memcpy(indexData, indices, indexDataSize);
    
    [quad setIndices:indexData count:4];
    [quad setVertices:vertexData count:20];
    
    free(vertexData);
    free(indexData);
    
    return quad;
}

@end
