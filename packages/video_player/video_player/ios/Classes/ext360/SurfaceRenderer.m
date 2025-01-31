//
//  SurfaceRenderer.m
//  video_player
//
//  Created by Eittipat K on 20/1/2565 BE.
//
#import "SurfaceRenderer.h"
#import "Video360Renderer.h"


@interface SurfaceRenderer()
@property(nonatomic) int format;
@property(nonatomic) int width;
@property(nonatomic) int height;
@property(nonatomic) Video360Renderer *videoRenderer;
@property(nonatomic) BOOL isEnable3D;
@end

@implementation SurfaceRenderer

- (instancetype)initWithVideoOutput:(AVPlayerItemVideoOutput *)videoOutput {
  self = [super initWithVideoOutput:videoOutput];
  if (self) {
    _format =0;
    _isEnable3D = NO;
    _width=1;
    _height=1;
    _videoRenderer = [[Video360Renderer alloc]init];
    [super setRenderer: _videoRenderer];
    [self setMediaFormat:_format];
  }
  return self;
}

- (void)setResolution:(int)width :(int)height {
  _width = width;
  _height = height;
  int surfaceWidth = _isEnable3D ? MIN(width, height) : width;
  int surfaceHeight = _isEnable3D ?MAX(width, height) : height;
  [super surfaceChanged:surfaceWidth :surfaceHeight];
}

- (void)setMediaFormat:(int)format {
  _format = format;
  _isEnable3D = format >> 3 == 1;
  int sphericalType = (format & 0x2) >> 1;
  int mediaType = (format & 0x1) + ((format & 0x4) >> 2);
  
  // Release previous mesh if exists
  if (_videoRenderer) {
    [_videoRenderer configureSurface:nil];
  }
  
  Mesh *mesh = nil;
  if(_isEnable3D) {
    mesh = [Sphere createUvSphereWithRadius:50
                                      latitudes:50
                                     longitudes:50
                             verticalFovDegrees:180
                           horizontalFovDegrees:sphericalType == 0 ? 180 : 360
                                    mediaFormat:mediaType];
    [super surfaceChanged:MIN(_width, _height) :MAX(_width, _height)];
  }else {
    mesh = [CanvasQuad createCanvasQuad];
    [super surfaceChanged:_width :_height];
  }
  [_videoRenderer configureSurface:mesh];
}

-(void)setCameraRotationWithRoll:(float)roll pitch:(float)pitch yaw:(float)yaw {
  if(_isEnable3D) {
    [_videoRenderer setCameraRotation:roll :pitch :yaw];
  }
}

-(void)dispose {
  [super surfaceDestroyed];
  if(_videoRenderer) {
    [_videoRenderer glShutdown];
    _videoRenderer = nil;
  }
  [super dispose];
}

@end
