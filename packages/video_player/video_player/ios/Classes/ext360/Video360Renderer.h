//
//  Video360Renderer.h
//  Pods
//
//  Created by Eittipat K on 20/1/2565 BE.
//

#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>
#import <Metal/Metal.h>
#import "Mesh.h"

@interface Video360Renderer : NSObject

- (void)configureSurface:(Mesh *)mesh;
- (void)onDrawFrame:(id<MTLTexture>)renderTarget;
- (void)onSurfaceChanged:(int)width :(int)height;
- (void)onSurfaceCreated;
- (void)setCameraRotation:(float)roll :(float)pitch :(float)yaw;
- (void)updateTexture:(CVPixelBufferRef)pixelBuffer;
- (void)glShutdown;

@end
