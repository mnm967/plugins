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
@property (nonatomic, strong) dispatch_queue_t renderQueue;
@end

@implementation MetalRenderer

- (instancetype)initWithVideoOutput:(AVPlayerItemVideoOutput *)videoOutput {
    self = [super init];
    if (self) {
        _renderQueue = dispatch_queue_create("com.yourcompany.metalRendererQueue", DISPATCH_QUEUE_SERIAL);
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
        
        NSThread *thread = [[NSThread alloc] initWithBlock:^{
            dispatch_sync(_renderQueue, ^{
                [self runLoopBlock:self];
            });
        }];
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

- (void)runLoopBlock:(MetalRenderer *)renderer {
    while (renderer.running) {
        @autoreleasepool {
            CFTimeInterval loopStart = CACurrentMediaTime();
            
            if (renderer.videoOutput == NULL)
                continue;
            
            CMTime outputTime = [renderer.videoOutput itemTimeForHostTime:CACurrentMediaTime()];
            renderer.newFrameAvailable = [renderer.videoOutput hasNewPixelBufferForItemTime:outputTime];
            
            CVPixelBufferRef inputSource = [renderer.videoOutput copyPixelBufferForItemTime:outputTime itemTimeForDisplay:NULL];
            if (inputSource == NULL)
                continue;
            
            CGSize inputSize = CGSizeMake(CVPixelBufferGetWidth(inputSource), CVPixelBufferGetHeight(inputSource));
            if (inputSize.width != renderer.renderSize.width || inputSize.height != renderer.renderSize.height) {
                [renderer surfaceChanged:inputSize.width :inputSize.height];
            }
            
            if (renderer.signalCreated) {
                if (renderer.renderer) {
                    [renderer.renderer onSurfaceCreated];
                }
                renderer.signalCreated = NO;
            }
            
            if (renderer.signalChanged) {
                [renderer resetTextureSize];
                [renderer.renderer onSurfaceChanged:renderer.renderSize.width :renderer.renderSize.height];
                renderer.signalChanged = NO;
                renderer.readyToDraw = YES;
            }
            
            if (renderer.readyToDraw) {
                if (renderer.renderer) {
                    [renderer.renderer updateTexture:inputSource];
                    [renderer.renderer onDrawFrame:renderer.renderTexture];
                }
            }
            
            CVBufferRelease(inputSource);
            
            CFTimeInterval waitDelta = 0.016 - (CACurrentMediaTime() - loopStart);
            if (waitDelta > 0) {
                [NSThread sleepForTimeInterval:waitDelta];
            }
        }
    }
    [renderer deinitMetal];
}

- (CVPixelBufferRef)copyPixelBuffer {
    CVPixelBufferRef buffer = NULL;
    @synchronized(self) {
        buffer = _output;
        if (buffer) {
            CVBufferRetain(buffer);
        }
    }
    return buffer;
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
        @synchronized(self) {
            if (_output) {
                CVPixelBufferRelease(_output);
                _output = NULL;
            }
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
        @synchronized(self) {
            if (_output) {
                CVPixelBufferRelease(_output);
                _output = NULL;
            }
        }
        
        // Flush and release texture cache in a synchronized block to prevent concurrent access
        @synchronized(self) {
            if (_textureCache) {
                CVMetalTextureCacheFlush(_textureCache, 0);
                CFRelease(_textureCache);
                _textureCache = NULL;
            }
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