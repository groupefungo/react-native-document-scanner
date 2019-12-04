#import "DocumentScannerView.h"
#import "IPDFCameraViewController.h"

@implementation DocumentScannerView

- (instancetype)init {
    self = [super init];
    __weak typeof(self) weakSelf = self;
    if (weakSelf) {
        [weakSelf setEnableBorderDetection:YES];
        [weakSelf setDelegate: weakSelf];
    }

    return weakSelf;
}


- (void) didDetectRectangle:(CIRectangleFeature *)rectangle withType:(IPDFRectangeType)type {
    __weak typeof(self) weakSelf = self;
    switch (type) {
        case IPDFRectangeTypeGood:
            weakSelf.stableCounter ++;
            break;
        default:
            weakSelf.stableCounter = 0;
            break;
    }


    if (weakSelf.stableCounter > weakSelf.detectionCountBeforeCapture){
        [weakSelf capture];
    }
}

- (void) capture {
    __weak typeof(self) weakSelf = self;
    [weakSelf captureImageWithCompletionHander:^(UIImage *croppedImage, UIImage *initialImage, CIRectangleFeature *rectangleFeature) {
      if (weakSelf.onPictureTaken) {
            NSData *croppedImageData = UIImageJPEGRepresentation(croppedImage, weakSelf.quality);
            NSData *initialImageData = UIImageJPEGRepresentation(initialImage, self.quality);

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
