//
//  IPDFCameraViewController.m
//  InstaPDF
//
//  Created by Maximilian Mackh on 06/01/15.
//  Copyright (c) 2015 mackh ag. All rights reserved.
//

#import "IPDFCameraViewController.h"

#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreImage/CoreImage.h>
#import <ImageIO/ImageIO.h>
#import <GLKit/GLKit.h>

@interface IPDFCameraViewController () <AVCaptureVideoDataOutputSampleBufferDelegate>

@property (atomic, strong) dispatch_queue_t sessionQueue;
@property (atomic, strong) AVCaptureSession *captureSession;
@property (atomic, strong) AVCaptureDevice *captureDevice;
@property (atomic, strong) EAGLContext *context;

@property (atomic, strong) AVCaptureStillImageOutput *stillImageOutput;
@property (atomic, strong) AVCaptureVideoDataOutput *dataOutput;

@property (atomic, assign) BOOL forceStop;
@property (atomic, assign) float lastDetectionRate;

@end

@implementation IPDFCameraViewController
{
    CIContext *_coreImageContext;
    GLuint _renderBuffer;
    GLKView *_glkView;

    BOOL _isStopped;

    CGFloat _imageDedectionConfidence;
    NSTimer *_borderDetectTimeKeeper;
    BOOL _borderDetectFrame;
    CIRectangleFeature *_borderDetectLastRectangleFeature;

    BOOL _isCapturing;
}

- (void)awakeFromNib
{
    [super awakeFromNib];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_backgroundMode) name:UIApplicationWillResignActiveNotification object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_foregroundMode) name:UIApplicationDidBecomeActiveNotification object:nil];
}

- (void)_backgroundMode
{
    self.forceStop = YES;
}

- (void)_foregroundMode
{
    self.forceStop = NO;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)createGLKView
{
    if (self.context) return;

    self.context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
    _glkView = [[GLKView alloc] initWithFrame:self.bounds];
    _glkView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _glkView.translatesAutoresizingMaskIntoConstraints = YES;
    _glkView.context = self.context;
    _glkView.contentScaleFactor = 1.0f;
    _glkView.drawableDepthFormat = GLKViewDrawableDepthFormat24;
    [self insertSubview:_glkView atIndex:0];
    glGenRenderbuffers(1, &_renderBuffer);
    glBindRenderbuffer(GL_RENDERBUFFER, _renderBuffer);
    _coreImageContext = [CIContext contextWithEAGLContext:self.context];
    [EAGLContext setCurrentContext:self.context];
}

- (void)setupCameraView
{
    [self createGLKView];

    AVCaptureDevice *device = nil;
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    for (AVCaptureDevice *possibleDevice in devices) {

        if ([possibleDevice position] != AVCaptureDevicePositionFront) {
            device = possibleDevice;
        }

    }
    if (!device) return;

    _imageDedectionConfidence = 0.0;

    self.captureSession = [[AVCaptureSession alloc] init];
    [self.captureSession beginConfiguration];
    self.captureDevice = device;

    self.sessionQueue = dispatch_queue_create( "session queue", DISPATCH_QUEUE_SERIAL );

    NSError *error = nil;
    AVCaptureDeviceInput* input = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
    self.captureSession.sessionPreset = AVCaptureSessionPresetPhoto;
    [self.captureSession addInput:input];

    self.dataOutput = [[AVCaptureVideoDataOutput alloc] init];
    [self.dataOutput setAlwaysDiscardsLateVideoFrames:YES];
    [self.dataOutput setVideoSettings:@{(id)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_32BGRA)}];
    [self.dataOutput setSampleBufferDelegate:self queue:self.sessionQueue];
    [self.captureSession addOutput:self.dataOutput];

    self.stillImageOutput = [[AVCaptureStillImageOutput alloc] init];
    [self.captureSession addOutput:self.stillImageOutput];

    AVCaptureConnection *connection = [self.dataOutput.connections firstObject];
    [connection setVideoOrientation:AVCaptureVideoOrientationPortrait];

    if (device.isFlashAvailable)
    {
        [device lockForConfiguration:nil];
        [device setFlashMode:AVCaptureFlashModeOff];
        [device unlockForConfiguration];

        if ([device isFocusModeSupported:AVCaptureFocusModeContinuousAutoFocus])
        {
            [device lockForConfiguration:nil];
            [device setFocusMode:AVCaptureFocusModeContinuousAutoFocus];
            [device unlockForConfiguration];
        }
    }

    [self.captureSession commitConfiguration];
}

- (void)setCameraViewType:(IPDFCameraViewType)cameraViewType
{
    __weak typeof(self) weakSelf = self;
    UIBlurEffect * effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
    UIVisualEffectView *viewWithBlurredBackground =[[UIVisualEffectView alloc] initWithEffect:effect];
    viewWithBlurredBackground.frame = weakSelf.bounds;
    [weakSelf insertSubview:viewWithBlurredBackground aboveSubview:_glkView];

    _cameraViewType = cameraViewType;

    // dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), self.sessionQueue, ^
   // {
   //     [viewWithBlurredBackground removeFromSuperview];
   // });
}

-(void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
    if (self.forceStop || _isStopped || _isCapturing || !CMSampleBufferIsValid(sampleBuffer)) return;

    CVPixelBufferRef pixelBuffer = (CVPixelBufferRef)CMSampleBufferGetImageBuffer(sampleBuffer);

    CIImage *image = [CIImage imageWithCVPixelBuffer:pixelBuffer];

    if (self.cameraViewType != IPDFCameraViewTypeNormal)
    {
        image = [self filteredImageUsingEnhanceFilterOnImage:image];
    }
    else
    {
        image = [self filteredImageUsingContrastFilterOnImage:image];
    }

    if (self.isBorderDetectionEnabled)
    {
        if (_borderDetectFrame)
        {
            _borderDetectLastRectangleFeature = [self biggestRectangleInRectangles:[[self highAccuracyRectangleDetector] featuresInImage:image]];
            _borderDetectFrame = NO;
        }

        if (_borderDetectLastRectangleFeature)
        {
            _imageDedectionConfidence += .5;

            image = [self drawHighlightOverlayForPoints:image topLeft:_borderDetectLastRectangleFeature.topLeft topRight:_borderDetectLastRectangleFeature.topRight bottomLeft:_borderDetectLastRectangleFeature.bottomLeft bottomRight:_borderDetectLastRectangleFeature.bottomRight];
        }
        else
        {
            _imageDedectionConfidence = 0.0f;
        }
    }

    if (self.context && _coreImageContext)
    {
        [_coreImageContext drawImage:image inRect:self.bounds fromRect:image.extent];
        [self.context presentRenderbuffer:GL_RENDERBUFFER];

        [_glkView setNeedsDisplay];
    }
}

- (void)enableBorderDetectFrame
{
    _borderDetectFrame = YES;
}

- (CIImage *)drawHighlightOverlayForPoints:(CIImage *)image topLeft:(CGPoint)topLeft topRight:(CGPoint)topRight bottomLeft:(CGPoint)bottomLeft bottomRight:(CGPoint)bottomRight
{
    CIImage *overlay = [CIImage imageWithColor:[[CIColor alloc] initWithColor:self.overlayColor]];
    overlay = [overlay imageByCroppingToRect:image.extent];
    overlay = [overlay imageByApplyingFilter:@"CIPerspectiveTransformWithExtent" withInputParameters:@{@"inputExtent":[CIVector vectorWithCGRect:image.extent],@"inputTopLeft":[CIVector vectorWithCGPoint:topLeft],@"inputTopRight":[CIVector vectorWithCGPoint:topRight],@"inputBottomLeft":[CIVector vectorWithCGPoint:bottomLeft],@"inputBottomRight":[CIVector vectorWithCGPoint:bottomRight]}];

    return [overlay imageByCompositingOverImage:image];
}

- (void)start
{
    _isStopped = NO;

    [self.captureSession startRunning];

    float detectionRefreshRate = _detectionRefreshRateInMS;
    CGFloat detectionRefreshRateInSec = detectionRefreshRate/100;

    if (_lastDetectionRate != _detectionRefreshRateInMS) {
        if (_borderDetectTimeKeeper) {
            [_borderDetectTimeKeeper invalidate];
        }
        _borderDetectTimeKeeper = [NSTimer scheduledTimerWithTimeInterval:detectionRefreshRateInSec target:self selector:@selector(enableBorderDetectFrame) userInfo:nil repeats:YES];
    }

    [self hideGLKView:NO completion:nil];

    _lastDetectionRate = _detectionRefreshRateInMS;
}

- (void)stop
{
    _isStopped = YES;
    __weak typeof(self) weakSelf = self;

    [weakSelf.captureSession stopRunning];

    if (_borderDetectTimeKeeper) {
        [_borderDetectTimeKeeper invalidate];
    }

    [weakSelf hideGLKView:YES completion:nil];


    weakSelf.captureSession=nil;
    weakSelf.dataOutput=nil;
    weakSelf.stillImageOutput=nil;
    weakSelf.sessionQueue=nil;
}

- (void)setEnableTorch:(BOOL)enableTorch
{
    _enableTorch = enableTorch;
    __weak typeof(self) weakSelf = self;

    AVCaptureDevice *device = weakSelf.captureDevice;
    if ([device hasTorch] && [device hasFlash])
    {
        [device lockForConfiguration:nil];
        if (enableTorch)
        {
            [device setTorchMode:AVCaptureTorchModeOn];
        }
        else
        {
            [device setTorchMode:AVCaptureTorchModeOff];
        }
        [device unlockForConfiguration];
    }
}

- (void)setUseFrontCam:(BOOL)useFrontCam
{
    _useFrontCam = useFrontCam;
    __weak typeof(self) weakSelf = self;
    [weakSelf stop];
    [weakSelf setupCameraView];
    [weakSelf start];
}


- (void)setContrast:(float)contrast
{
    _contrast = contrast;
}

- (void)setSaturation:(float)saturation
{
    _saturation = saturation;
}

- (void)setBrightness:(float)brightness
{
    _brightness = brightness;
}

- (void)setDetectionRefreshRateInMS:(NSInteger)detectionRefreshRateInMS
{
    _detectionRefreshRateInMS = detectionRefreshRateInMS;
}

- (void)focusAtPoint:(CGPoint)point completionHandler:(void(^)(void))completionHandler
{
    AVCaptureDevice *device = self.captureDevice;
    CGPoint pointOfInterest = CGPointZero;
    CGSize frameSize = self.bounds.size;
    pointOfInterest = CGPointMake(point.y / frameSize.height, 1.f - (point.x / frameSize.width));

    if ([device isFocusPointOfInterestSupported] && [device isFocusModeSupported:AVCaptureFocusModeAutoFocus])
    {
        NSError *error;
        if ([device lockForConfiguration:&error])
        {
            if ([device isFocusModeSupported:AVCaptureFocusModeContinuousAutoFocus])
            {
                [device setFocusMode:AVCaptureFocusModeContinuousAutoFocus];
                [device setFocusPointOfInterest:pointOfInterest];
            }

            if([device isExposurePointOfInterestSupported] && [device isExposureModeSupported:AVCaptureExposureModeContinuousAutoExposure])
            {
                [device setExposurePointOfInterest:pointOfInterest];
                [device setExposureMode:AVCaptureExposureModeContinuousAutoExposure];
                completionHandler();
            }

            [device unlockForConfiguration];
        }
    }
    else
    {
        completionHandler();
    }
}

- (void)captureImageWithCompletionHander:(void(^)(UIImage *data, UIImage *initialData, CIRectangleFeature *rectangleFeature))completionHandler
{
    if (_isStopped || _isCapturing) return;

    [self hideGLKView:YES completion:nil];

    _isCapturing = YES;

    AVCaptureConnection *videoConnection = nil;
    for (AVCaptureConnection *connection in self.stillImageOutput.connections)
    {
        for (AVCaptureInputPort *port in [connection inputPorts])
        {
            if ([[port mediaType] isEqual:AVMediaTypeVideo] )
            {
                videoConnection = connection;
                break;
            }
        }
        if (videoConnection) break;
    }

    [self.stillImageOutput captureStillImageAsynchronouslyFromConnection:videoConnection completionHandler: ^(CMSampleBufferRef imageSampleBuffer, NSError *error)
     {
         NSData *imageData = [AVCaptureStillImageOutput jpegStillImageNSDataRepresentation:imageSampleBuffer];

         if (self.cameraViewType == IPDFCameraViewTypeBlackAndWhite || self.isBorderDetectionEnabled)
         {
             CIImage *enhancedImage = [CIImage imageWithData:imageData];

             if (self.cameraViewType == IPDFCameraViewTypeBlackAndWhite)
             {
                 enhancedImage = [self filteredImageUsingEnhanceFilterOnImage:enhancedImage];
             }
             else
             {
                 enhancedImage = [self filteredImageUsingContrastFilterOnImage:enhancedImage];
             }

             if (self.isBorderDetectionEnabled && rectangleDetectionConfidenceHighEnough(self->_imageDedectionConfidence))
             {
                 CIRectangleFeature *rectangleFeature = [self biggestRectangleInRectangles:[[self highAccuracyRectangleDetector] featuresInImage:enhancedImage]];

                 if (rectangleFeature)
                 {

                     CIContext* context = [CIContext context];
                     CGImageRef cgCroppedImage = [context createCGImage:enhancedImage fromRect:rectangleFeature.bounds];
                     UIImage* newImage = [UIImage imageWithCGImage:cgCroppedImage];
                     UIImage *initialImage = [UIImage imageWithData:imageData];
                     CGImageRelease(cgCroppedImage);

                     completionHandler(newImage, initialImage, rectangleFeature);
                 }
             } else {
                 [self hideGLKView:NO completion:nil];
                 UIImage *initialImage = [UIImage imageWithData:imageData];
                 completionHandler(initialImage, initialImage, nil);
             }
         }
         else
         {
             [self hideGLKView:NO completion:nil];
             UIImage *initialImage = [UIImage imageWithData:imageData];
             completionHandler(initialImage, initialImage, nil);
         }

         self->_isCapturing = NO;
     }];
}

- (void)hideGLKView:(BOOL)hidden completion:(void(^)(void))completion
{
    [UIView animateWithDuration:0.1 animations:^
    {
        self->_glkView.alpha = (hidden) ? 0.0 : 1.0;
    }
    completion:^(BOOL finished)
    {
        if (!completion) return;
        completion();
    }];
}

- (CIImage *)filteredImageUsingEnhanceFilterOnImage:(CIImage *)image
{
    return [CIFilter filterWithName:@"CIColorControls" keysAndValues:kCIInputImageKey, image, @"inputBrightness", @(self.brightness), @"inputContrast", @(self.contrast), @"inputSaturation", @(self.saturation), nil].outputImage;
}

- (CIImage *)filteredImageUsingContrastFilterOnImage:(CIImage *)image
{
    return [CIFilter filterWithName:@"CIColorControls" withInputParameters:@{@"inputContrast":@(1.0),kCIInputImageKey:image}].outputImage;
}

- (CIImage *)correctPerspectiveForImage:(CIImage *)image withFeatures:(CIRectangleFeature *)rectangleFeature
{
  NSMutableDictionary *rectangleCoordinates = [NSMutableDictionary new];
  CGPoint newLeft = CGPointMake(rectangleFeature.topLeft.x + 30, rectangleFeature.topLeft.y);
  CGPoint newRight = CGPointMake(rectangleFeature.topRight.x, rectangleFeature.topRight.y);
  CGPoint newBottomLeft = CGPointMake(rectangleFeature.bottomLeft.x + 30, rectangleFeature.bottomLeft.y);
  CGPoint newBottomRight = CGPointMake(rectangleFeature.bottomRight.x, rectangleFeature.bottomRight.y);

  rectangleCoordinates[@"inputTopLeft"] = [CIVector vectorWithCGPoint:newLeft];
  rectangleCoordinates[@"inputTopRight"] = [CIVector vectorWithCGPoint:newRight];
  rectangleCoordinates[@"inputBottomLeft"] = [CIVector vectorWithCGPoint:newBottomLeft];
  rectangleCoordinates[@"inputBottomRight"] = [CIVector vectorWithCGPoint:newBottomRight];
  return [image imageByApplyingFilter:@"CIPerspectiveCorrection" withInputParameters:rectangleCoordinates];
}

- (CIDetector *)rectangleDetetor
{
    static CIDetector *detector = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^
    {
          detector = [CIDetector detectorOfType:CIDetectorTypeRectangle context:nil options:@{CIDetectorAccuracy : CIDetectorAccuracyLow,CIDetectorTracking : @(YES)}];
    });
    return detector;
}

- (CIDetector *)highAccuracyRectangleDetector
{
    static CIDetector *detector = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^
    {
        detector = [CIDetector detectorOfType:CIDetectorTypeRectangle context:nil options:@{CIDetectorAccuracy : CIDetectorAccuracyHigh, CIDetectorReturnSubFeatures: @(YES) }];
    });
    return detector;
}

- (CIRectangleFeature *)biggestRectangleInRectangles:(NSArray *)rectangles
{
    if (![rectangles count]) return nil;

    float halfPerimiterValue = 0;

    CIRectangleFeature *biggestRectangle = [rectangles firstObject];

    for (CIRectangleFeature *rect in rectangles)
    {
        CGPoint p1 = rect.topLeft;
        CGPoint p2 = rect.topRight;
        CGFloat width = hypotf(p1.x - p2.x, p1.y - p2.y);

        CGPoint p3 = rect.topLeft;
        CGPoint p4 = rect.bottomLeft;
        CGFloat height = hypotf(p3.x - p4.x, p3.y - p4.y);

        CGFloat currentHalfPerimiterValue = height + width;

        if (halfPerimiterValue < currentHalfPerimiterValue)
        {
            halfPerimiterValue = currentHalfPerimiterValue;
            biggestRectangle = rect;
        }
    }

    if (self.delegate) {
        [self.delegate didDetectRectangle:biggestRectangle withType:[self typeForRectangle:biggestRectangle]];
    }

    return biggestRectangle;
}

- (IPDFRectangeType) typeForRectangle: (CIRectangleFeature*) rectangle {
    if (fabs(rectangle.topRight.y - rectangle.topLeft.y) > 100 ||
        fabs(rectangle.topRight.x - rectangle.bottomRight.x) > 100 ||
        fabs(rectangle.topLeft.x - rectangle.bottomLeft.x) > 100 ||
        fabs(rectangle.bottomLeft.y - rectangle.bottomRight.y) > 100) {
        return IPDFRectangeTypeBadAngle;
    } else if ((_glkView.frame.origin.y + _glkView.frame.size.height) - rectangle.topLeft.y > 150 ||
               (_glkView.frame.origin.y + _glkView.frame.size.height) - rectangle.topRight.y > 150 ||
               _glkView.frame.origin.y - rectangle.bottomLeft.y > 150 ||
               _glkView.frame.origin.y - rectangle.bottomRight.y > 150) {
        return IPDFRectangeTypeTooFar;
    }
    return IPDFRectangeTypeGood;
}

BOOL rectangleDetectionConfidenceHighEnough(float confidence)
{
    return (confidence > 1.0);
}

@end
