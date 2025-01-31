//
//  Mesh.h
//  video_player
//
//  Created by Eittipat K on 20/1/2565 BE.
//

#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>
#import <Metal/Metal.h>
#import <simd/simd.h>

NS_ASSUME_NONNULL_BEGIN

@interface Mesh : NSObject {
@protected
    float* _vertices;
    uint16_t* _indices;
    NSUInteger _vertexCount;
    NSUInteger _indexCount;
    NSUInteger _length;
}

- (instancetype)initWithVertices:(float*)vertices length:(NSUInteger)length;
- (void)getVertices:(float**)vertices count:(NSUInteger*)count;
- (void)getIndices:(uint16_t**)indices count:(NSUInteger*)count;
- (void)setVertices:(float*)vertices count:(NSUInteger)count;
- (void)setIndices:(uint16_t*)indices count:(NSUInteger)count;
- (NSUInteger)indexCount;

@property (nonatomic, readonly) id<MTLBuffer> vertexBuffer;
@property (nonatomic, readonly) id<MTLBuffer> indexBuffer;

@end

@interface Sphere : Mesh

+ (instancetype)createUvSphereWithRadius:(float)radius
                              latitudes:(int)latitudes
                             longitudes:(int)longitudes
                     verticalFovDegrees:(float)verticalFovDegrees
                   horizontalFovDegrees:(float)horizontalFovDegrees
                            mediaFormat:(int)mediaFormat;

@end

@interface CanvasQuad : Mesh

+ (instancetype)createCanvasQuad;

@end

NS_ASSUME_NONNULL_END

