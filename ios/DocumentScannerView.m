#import "DocumentScannerView.h"
#import "IPDFCameraViewController.h"

@implementation DocumentScannerView

- (instancetype)init {
    self = [super init];
    if (self) {
        [self setEnableBorderDetection:YES];
        [self setDelegate: self];
    }

    return self;
}

- (void) didDetectRectangle:(CIRectangleFeature *)rectangle withType:(IPDFRectangeType)type {
    switch (type) {
        case IPDFRectangeTypeGood:
            self.stableCounter ++;
            break;
        default:
            self.stableCounter = 0;
            break;
    }

    if (self.stableCounter > self.detectionCountBeforeCapture){
        [self capture];
    }
}

- (void) capture {
    __weak typeof(self) weakSelf = self;
    [weakSelf captureImageWithCompletionHander:^(UIImage *croppedImage, UIImage *initialImage, CIRectangleFeature *rectangleFeature) {
      if (weakSelf.onPictureTaken) {
            NSData *croppedImageData = UIImageJPEGRepresentation(croppedImage, weakSelf.quality);
            NSData *initialImageData = UIImageJPEGRepresentation(initialImage, weakSelf.quality);

            /*
             RectangleCoordinates expects a rectanle viewed from portrait,
             while rectangleFeature returns a rectangle viewed from landscape, which explains the nonsense of the mapping below.
             Sorry about that.
             */
            NSDictionary *rectangleCoordinates = [NSNull null];

           NSString *dir = NSTemporaryDirectory();
           NSString *croppedFilePath = [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"cropped_img_%i.jpeg",(int)[NSDate date].timeIntervalSince1970]];
           NSString *initialFilePath = [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"initial_img_%i.jpeg",(int)[NSDate date].timeIntervalSince1970]];

          [croppedImageData writeToFile:croppedFilePath atomically:YES];
          [initialImageData writeToFile:initialFilePath atomically:YES];

           weakSelf.onPictureTaken(@{
                                 @"croppedImage": croppedFilePath,
                                 @"initialImage": initialFilePath,
                                 @"rectangleCoordinates": rectangleCoordinates });

        }

        if (!weakSelf.captureMultiple) {
          [weakSelf stop];
        }
    }];

}


@end
