#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <Metal/Metal.h>
#import "Video360Renderer.h"

@interface MetalRenderer : NSObject

@property (nonatomic, readonly) BOOL disposed;

- (instancetype)initWithVideoOutput:(AVPlayerItemVideoOutput *)videoOutput;
- (void)setRenderer:(Video360Renderer *)renderer;
- (void)surfaceCreated;
- (void)surfaceChanged:(int)width :(int)height;
- (void)surfaceDestroyed;
- (CVPixelBufferRef)copyPixelBuffer;
- (void)dispose;

@end 