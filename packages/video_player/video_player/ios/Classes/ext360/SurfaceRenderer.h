//
//  SurfaceRenderer.h
//  video_player
//
//  Created by Eittipat K on 20/1/2565 BE.
//
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import "MetalRenderer.h"

@interface SurfaceRenderer : MetalRenderer

- (instancetype)initWithVideoOutput:(AVPlayerItemVideoOutput *)videoOutput;
- (void)setResolution:(int)width :(int)height;
- (void)setMediaFormat:(int)format;
- (void)setCameraRotationWithRoll:(float)roll pitch:(float)pitch yaw:(float)yaw;
- (void)dispose;

@end
