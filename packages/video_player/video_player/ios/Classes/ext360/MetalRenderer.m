#import "MetalRenderer.h"

@interface MetalRenderer()
@property (strong, nonatomic) id<MTLDevice> device;
@property (strong, nonatomic) id<MTLCommandQueue> commandQueue;
@property (strong, nonatomic) Video360Renderer *renderer;
@property (nonatomic) AVPlayerItemVideoOutput *videoOutput;

@property (nonatomic) CVMetalTextureCacheRef textureCache;
@property (nonatomic) id<MTLTexture> renderTexture;
@property (nonatomic) CVPixelBufferRef output;
@property (nonatomic) CGSize renderSize;
@property (nonatomic) BOOL running;
@property (nonatomic) BOOL signalCreated;
@property (nonatomic) BOOL signalChanged;
@property (nonatomic) BOOL readyToDraw;
@property (nonatomic) BOOL newFrameAvailable;
@end

@implementation MetalRenderer

- (instancetype)initWithVideoOutput:(AVPlayerItemVideoOutput *)videoOutput {
    self = [super init];
    if (self) {
        _videoOutput = videoOutput;
        _running = YES;
        _disposed = NO;
        _signalCreated = NO;
        _signalChanged = NO;
        _readyToDraw = NO;
        _newFrameAvailable = NO;
        _textureCache = NULL;
        
        // Initialize Metal
        [self initMetal];
        
        NSThread *thread = [[NSThread alloc] initWithTarget:self selector:@selector(run) object:nil];
        thread.name = @"MetalRenderer";
        [thread start];
    }
    return self;
}

- (void)setRenderer:(Video360Renderer *)renderer {
    _renderer = renderer;
}

- (void)surfaceCreated {
    _signalCreated = YES;
}

- (void)surfaceChanged:(int)width :(int)height {
    _signalChanged = YES;
    _renderSize = CGSizeMake((float)width, (float)height);
}

- (void)surfaceDestroyed {
    _running = NO;
}

- (void)run {
    while (_running) {
        @autoreleasepool {
            CFTimeInterval loopStart = CACurrentMediaTime();
            
            if (_videoOutput == NULL)
                continue;
            
            CMTime outputTime = [_videoOutput itemTimeForHostTime:CACurrentMediaTime()];
            _newFrameAvailable = [_videoOutput hasNewPixelBufferForItemTime:outputTime];
            
            CVPixelBufferRef inputSource = [_videoOutput copyPixelBufferForItemTime:outputTime itemTimeForDisplay:NULL];
            if (inputSource == NULL)
                continue;
            
            CGSize inputSize = CGSizeMake(CVPixelBufferGetWidth(inputSource), CVPixelBufferGetHeight(inputSource));
            if (inputSize.width != _renderSize.width || inputSize.height != _renderSize.height) {
                [self surfaceChanged:inputSize.width :inputSize.height];
            }
            
            if (_signalCreated) {
                [_renderer onSurfaceCreated];
                _signalCreated = NO;
            }
            
            if (_signalChanged) {
                [self resetTextureSize];
                [_renderer onSurfaceChanged:_renderSize.width :_renderSize.height];
                _signalChanged = NO;
                _readyToDraw = YES;
            }
            
            if (_readyToDraw) {
                [_renderer updateTexture:inputSource];
                [_renderer onDrawFrame:_renderTexture];
            }
            
            CVBufferRelease(inputSource);
            
            CFTimeInterval waitDelta = 0.016 - (CACurrentMediaTime() - loopStart);
            if (waitDelta > 0) {
                [NSThread sleepForTimeInterval:waitDelta];
            }
        }
    }
    [self deinitMetal];
}

- (CVPixelBufferRef)copyPixelBuffer {
    CVBufferRetain(_output);
    return _output;
}

- (void)initMetal {
    @try {
        _device = MTLCreateSystemDefaultDevice();
        _commandQueue = [_device newCommandQueue];
        
        // Create Metal texture cache with error handling
        CVReturn result = CVMetalTextureCacheCreate(kCFAllocatorDefault,
                                                  NULL,
                                                  _device,
                                                  NULL,
                                                  &_textureCache);
        if (result != kCVReturnSuccess) {
            NSLog(@"Warning: Failed to create texture cache");
        }
    } @catch (NSException *exception) {
        NSLog(@"Warning: Exception in initMetal: %@", exception);
    }
}

- (void)resetTextureSize {
    @try {
        // Create attributes dictionary only once
        static CFDictionaryRef empty = NULL;
        static CFMutableDictionaryRef attrs = NULL;
        
        if (!empty || !attrs) {
            empty = CFDictionaryCreate(kCFAllocatorDefault,
                                     NULL,
                                     NULL,
                                     0,
                                     &kCFTypeDictionaryKeyCallBacks,
                                     &kCFTypeDictionaryValueCallBacks);
            
            attrs = CFDictionaryCreateMutable(kCFAllocatorDefault,
                                            1,
                                            &kCFTypeDictionaryKeyCallBacks,
                                            &kCFTypeDictionaryValueCallBacks);
            
            CFDictionarySetValue(attrs, kCVPixelBufferIOSurfacePropertiesKey, empty);
        }
        
        // Release old output buffer if it exists
        if (_output) {
            CVPixelBufferRelease(_output);
            _output = NULL;
        }
        
        // Create pixel buffer with optimal settings
        CVReturn result = CVPixelBufferCreate(kCFAllocatorDefault,
                                            _renderSize.width,
                                            _renderSize.height,
                                            kCVPixelFormatType_32BGRA,
                                            attrs,
                                            &_output);
        
        if (result != kCVReturnSuccess) {
            NSLog(@"Warning: Failed to create pixel buffer");
            return;
        }
        
        // Create Metal texture from pixel buffer
        if (_textureCache) {
            CVMetalTextureRef metalTextureRef = NULL;
            result = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                             _textureCache,
                                                             _output,
                                                             NULL,
                                                             MTLPixelFormatBGRA8Unorm,
                                                             _renderSize.width,
                                                             _renderSize.height,
                                                             0,
                                                             &metalTextureRef);
            
            if (result == kCVReturnSuccess && metalTextureRef) {
                _renderTexture = CVMetalTextureGetTexture(metalTextureRef);
                CFRelease(metalTextureRef);
            } else {
                NSLog(@"Warning: Failed to create Metal texture from pixel buffer");
            }
        }
    } @catch (NSException *exception) {
        NSLog(@"Warning: Exception in resetTextureSize: %@", exception);
    }
}

- (void)deinitMetal {
    @try {
        // Release render texture first
        _renderTexture = nil;
        
        // Release output buffer
        if (_output) {
            CVPixelBufferRelease(_output);
            _output = NULL;
        }
        
        // Flush and release texture cache
        if (_textureCache) {
            CVMetalTextureCacheFlush(_textureCache, 0);
            CFRelease(_textureCache);
            _textureCache = NULL;
        }
        
        // Release Metal resources
        _commandQueue = nil;
        _device = nil;
        _renderer = nil;
        
        NSLog(@"Metal deinit OK.");
    } @catch (NSException *exception) {
        NSLog(@"Warning: Exception in deinitMetal: %@", exception);
    }
}

- (void)dispose {
    _running = NO;
    [self deinitMetal];
}

@end 