#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <CoreVideo/CoreVideo.h>
#import "Mesh.h"

@interface Video360MetalRenderer : NSObject

- (instancetype)initWithDevice:(id<MTLDevice>)device;
- (void)configureSurface:(Mesh *)mesh;
- (void)drawWithCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
                      texture:(id<MTLTexture>)texture
                      inView:(MTKView *)view;
- (void)updateViewportWidth:(int)width height:(int)height;
- (void)setCameraRotation:(float)roll pitch:(float)pitch yaw:(float)yaw;
- (void)updateTexture:(CVPixelBufferRef)pixelBuffer;
- (void)shutdown;

@end 