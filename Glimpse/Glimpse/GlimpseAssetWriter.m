//
//  GlimpseAssetWriter.m
//  Glimpse
//
//  Created by Wess Cope on 3/25/13.
//  Copyright (c) 2013 Wess Cope. All rights reserved.
//

#import "GlimpseAssetWriter.h"
#import <AVFoundation/AVFoundation.h>

@interface GlimpseAssetWriter()
{
    CFTimeInterval      _timestamp;
    int32_t            _frameRate;
    uint64_t            _frameCount;
    dispatch_queue_t    _queue;
}

@property (strong, nonatomic) AVAssetWriter                         *writer;
@property (strong, nonatomic) AVAssetWriterInput                    *input;
@property (strong, nonatomic) AVAssetWriterInputPixelBufferAdaptor  *adapter;
@property (strong, nonatomic) CADisplayLink                         *displayLink;
@property (nonatomic, assign) NSInteger presentationI;

@end

@implementation GlimpseAssetWriter
@synthesize fileOutputURL   = _fileOutputURL;
@synthesize writer          = _writer;
@synthesize displayLink     = _displayLink;

static NSString *const GlimpseAssetWriterQueueName = @"com.Glimpse.asset.writer.queue";

- (id)init
{
    self = [super init];
    if (self)
    {
        self.size               = [[UIScreen mainScreen] bounds].size;
        self.framesPerSecond    = 24;
        
        _frameRate  = (int32_t)self.framesPerSecond;
        _queue      = dispatch_queue_create([GlimpseAssetWriterQueueName cStringUsingEncoding:NSUTF8StringEncoding], 0);
    }
    return self;
}

- (NSURL *)createFileOutputURL
{
    NSString *documentDirectory = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    NSTimeInterval timestamp    = [[NSDate date] timeIntervalSince1970];
    NSString *filename          = [NSString stringWithFormat:@"glimpse_%08x.mov", (int)timestamp];
    NSString *path              = [NSString stringWithFormat:@"%@/%@", documentDirectory, filename];
    NSFileManager *fileManager  = [NSFileManager defaultManager];
    
    if([fileManager fileExistsAtPath:path])
        [fileManager removeItemAtPath:path error:nil];
    
    NSLog(@"OUTPUT: %@", path);
    return [NSURL fileURLWithPath:path];
}

- (AVAssetWriter *)writer
{
    if(_writer)
        return _writer;
    
    _fileOutputURL = [self createFileOutputURL];
    
    NSError *error = nil;
    _writer = [[AVAssetWriter alloc] initWithURL:self.fileOutputURL fileType:AVFileTypeQuickTimeMovie error:&error];
    NSAssert(error == nil, error.debugDescription);
    
    NSDictionary *settings = @{
                               AVVideoCodecKey: AVVideoCodecH264,
                               AVVideoWidthKey: @(self.size.width),
                               AVVideoHeightKey: @(self.size.height)
                               };
    
    self.input = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:settings];
    
    NSDictionary *attributes = @{
                                 (NSString *)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32ARGB),
                                 (NSString *)kCVPixelBufferWidthKey: @(self.size.width),
                                 (NSString *)kCVPixelBufferHeightKey: @(self.size.height)
                                 };
    self.adapter = [AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput:self.input sourcePixelBufferAttributes:attributes];
    
    [self.writer addInput:self.input];
    
    self.input.expectsMediaDataInRealTime = NO;
    
    return _writer;
}

- (CVPixelBufferRef)pixelBufferForImage:(UIImage *)image
{
    CGImageRef cgImage = image.CGImage; 
    
    NSDictionary *options = @{
                              (NSString *)kCVPixelBufferCGImageCompatibilityKey: @(YES),
                              (NSString *)kCVPixelBufferCGBitmapContextCompatibilityKey: @(YES)
                              };
    CVPixelBufferRef buffer = NULL;
    CVPixelBufferCreate(kCFAllocatorDefault, CGImageGetWidth(cgImage), CGImageGetHeight(cgImage), kCVPixelFormatType_32ARGB, (__bridge CFDictionaryRef)options, &buffer);
    
    CVPixelBufferLockBaseAddress(buffer, 0);
    
    void *data                  = CVPixelBufferGetBaseAddress(buffer);
    CGColorSpaceRef colorSpace  = CGColorSpaceCreateDeviceRGB();
    CGContextRef context        = CGBitmapContextCreate(data, CGImageGetWidth(cgImage), CGImageGetHeight(cgImage), 8, CVPixelBufferGetBytesPerRow(buffer), colorSpace, (kCGBitmapAlphaInfoMask & kCGImageAlphaNoneSkipFirst));
    CGContextDrawImage(context, CGRectMake(0.0f, 0.0f, CGImageGetWidth(cgImage), CGImageGetHeight(cgImage)), cgImage);
    
    CGColorSpaceRelease(colorSpace);
    CGContextRelease(context);
    
    CVPixelBufferUnlockBaseAddress(buffer, 0);
    
    return buffer;
}

- (void)writeFrameWithImage:(UIImage *)image
{
    dispatch_async(_queue, ^{
        __block CVPixelBufferRef buffer = [self pixelBufferForImage:image];
        BOOL success = [self.adapter appendPixelBuffer:buffer withPresentationTime:CMTimeMake(self.presentationI, self->_frameRate)];
        self.presentationI++;
        assert(success);
        if(buffer)
            CVBufferRelease(buffer);
    });
}

- (void)start {
    [self.writer startWriting];
    [self.writer startSessionAtSourceTime:kCMTimeZero];
}

- (void)writeVideoFromImageFrames:(void(^)(NSURL *outputPath))callback
{
    dispatch_async(_queue, ^{
        [self.input markAsFinished];
        [self.writer finishWritingWithCompletionHandler:^{
            if(callback)
                callback(self.fileOutputURL);
        }];
    });
}

@end
