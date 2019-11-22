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
    /*if (self.onRectangleDetect) {
        self.onRectangleDetect(@{@"stableCounter": @(self.stableCounter), @"lastDetectionType": @(type)});
    }*/

    if (weakSelf.stableCounter > weakSelf.detectionCountBeforeCapture){
        [weakSelf capture];
    }
}

- (void) capture {
    __weak typeof(self) weakSelf = self;
    [weakSelf captureImageWithCompletionHander:^(UIImage *croppedImage/*, UIImage *initialImage, CIRectangleFeature *rectangleFeature*/) {
      if (weakSelf.onPictureTaken) {
            NSData *croppedImageData = UIImageJPEGRepresentation(croppedImage, weakSelf.quality);

            /*if (initialImage.imageOrientation != UIImageOrientationUp) {
                UIGraphicsBeginImageContextWithOptions(initialImage.size, false, initialImage.scale);
                [initialImage drawInRect:CGRectMake(0, 0, initialImage.size.width
                                                    , initialImage.size.height)];
                initialImage = UIGraphicsGetImageFromCurrentImageContext();
                UIGraphicsEndImageContext();
            }
            NSData *initialImageData = UIImageJPEGRepresentation(initialImage, self.quality);
*/
            /*
             RectangleCoordinates expects a rectanle viewed from portrait,
             while rectangleFeature returns a rectangle viewed from landscape, which explains the nonsense of the mapping below.
             Sorry about that.
             */
            /*NSDictionary *rectangleCoordinates = rectangleFeature ? @{
                                     @"topLeft": @{ @"y": @(rectangleFeature.bottomLeft.x + 30), @"x": @(rectangleFeature.bottomLeft.y)},
                                     @"topRight": @{ @"y": @(rectangleFeature.topLeft.x + 30), @"x": @(rectangleFeature.topLeft.y)},
                                     @"bottomLeft": @{ @"y": @(rectangleFeature.bottomRight.x), @"x": @(rectangleFeature.bottomRight.y)},
                                     @"bottomRight": @{ @"y": @(rectangleFeature.topRight.x), @"x": @(rectangleFeature.topRight.y)},
                                     } : [NSNull null];*/
            if (weakSelf.useBase64) {
              weakSelf.onPictureTaken(@{
                                    @"croppedImage": [croppedImageData base64EncodedStringWithOptions:NSDataBase64Encoding64CharacterLineLength]/*,
                                    @"initialImage": [initialImageData base64EncodedStringWithOptions:NSDataBase64Encoding64CharacterLineLength],
                                    @"rectangleCoordinates": rectangleCoordinates*/ });
            }
            else {
                NSString *dir = NSTemporaryDirectory();
                /*if (self.saveInAppDocument) {
                    dir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
                }*/
               //NSString *croppedFilePath = [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"cropped_img_%i.png",(int)[NSDate date].timeIntervalSince1970]];
               NSString *croppedFilePath = [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"cropped_img_%i.jpeg",(int)[NSDate date].timeIntervalSince1970]];
               //NSString *initialFilePath = [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"initial_img_%i.jpeg",(int)[NSDate date].timeIntervalSince1970]];

              [croppedImageData writeToFile:croppedFilePath atomically:YES];
              //[initialImageData writeToFile:initialFilePath atomically:YES];

               weakSelf.onPictureTaken(@{
                                     @"croppedImage": croppedFilePath /*,
                                     @"initialImage": initialFilePath,
                                     @"rectangleCoordinates": rectangleCoordinates*/ });
            }
        }

        if (!weakSelf.captureMultiple) {
          [weakSelf stop];
        }
    }];

}


@end
