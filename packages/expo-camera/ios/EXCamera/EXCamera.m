#import <AVFoundation/AVFoundation.h>

#import <UMBarCodeScannerInterface/UMBarCodeScannerProviderInterface.h>
#import <EXCamera/EXCamera.h>
#import <EXCamera/EXCameraUtils.h>
#import <EXCamera/EXCameraManager.h>
#import <UMCore/UMAppLifecycleService.h>
#import <UMCore/UMUtilities.h>
#import <UMFaceDetectorInterface/UMFaceDetectorManagerProvider.h>
#import <UMFileSystemInterface/UMFileSystemInterface.h>
#import <UMPermissionsInterface/UMPermissionsInterface.h>

@interface EXCamera ()

@property (nonatomic, weak) id<UMFileSystemInterface> fileSystem;
@property (nonatomic, weak) UMModuleRegistry *moduleRegistry;
@property (nonatomic, strong) id<UMFaceDetectorManager> faceDetectorManager;
@property (nonatomic, strong) id<UMBarCodeScannerInterface> barCodeScanner;
@property (nonatomic, weak) id<UMPermissionsInterface> permissionsManager;
@property (nonatomic, weak) id<UMAppLifecycleService> lifecycleManager;

@property (nonatomic, assign, getter=isSessionPaused) BOOL paused;

@property (nonatomic, strong) NSDictionary *photoCaptureOptions;
@property (nonatomic, strong) UMPromiseResolveBlock photoCapturedResolve;
@property (nonatomic, strong) UMPromiseRejectBlock photoCapturedReject;

@property (nonatomic, strong) UMPromiseResolveBlock videoRecordedResolve;
@property (nonatomic, strong) UMPromiseRejectBlock videoRecordedReject;

@property (nonatomic, copy) UMDirectEventBlock onCameraReady;
@property (nonatomic, copy) UMDirectEventBlock onMountError;
@property (nonatomic, copy) UMDirectEventBlock onPictureSaved;

@property (nonatomic, copy) UMDirectEventBlock onBarCodeScanned;
@property (nonatomic, copy) UMDirectEventBlock onFacesDetected;

@end

@implementation EXCamera

static NSDictionary *defaultFaceDetectorOptions = nil;

- (id)initWithModuleRegistry:(UMModuleRegistry *)moduleRegistry
{
  if ((self = [super init])) {
    _moduleRegistry = moduleRegistry;
    _session = [AVCaptureSession new];
    _sessionQueue = dispatch_queue_create("cameraQueue", DISPATCH_QUEUE_SERIAL);
    _faceDetectorManager = [self createFaceDetectorManager];
    _barCodeScanner = [self createBarCodeScanner];
    _lifecycleManager = [moduleRegistry getModuleImplementingProtocol:@protocol(UMAppLifecycleService)];
    _fileSystem = [moduleRegistry getModuleImplementingProtocol:@protocol(UMFileSystemInterface)];
    _permissionsManager = [moduleRegistry getModuleImplementingProtocol:@protocol(UMPermissionsInterface)];
#if !(TARGET_IPHONE_SIMULATOR)
    _previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:_session];
    _previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    _previewLayer.needsDisplayOnBoundsChange = YES;
#endif
    _paused = NO;
    _pictureSize = AVCaptureSessionPresetHigh;
    [self changePreviewOrientation:[UIApplication sharedApplication].statusBarOrientation];
    [self initializeCaptureSessionInput];
    [self startSession];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(orientationChanged:)
                                                 name:UIDeviceOrientationDidChangeNotification
                                               object:nil];
    [_lifecycleManager registerAppLifecycleListener:self];
  }
  return self;
}

- (void)onReady:(NSDictionary *)event
{
  if (_onCameraReady) {
    _onCameraReady(nil);
  }
}

- (void)onMountingError:(NSDictionary *)event
{
  if (_onMountError) {
    _onMountError(event);
  }
}

- (void)onBarCodeScanned:(NSDictionary *)event
{
  if (_onBarCodeScanned) {
    _onBarCodeScanned(event);
  }
}

- (void)onPictureSaved:(NSDictionary *)event
{
  if (_onPictureSaved) {
    _onPictureSaved(event);
  }
}

- (void)layoutSubviews
{
  [super layoutSubviews];
  _previewLayer.frame = self.bounds;
  [self setBackgroundColor:[UIColor blackColor]];
  [self.layer insertSublayer:_previewLayer atIndex:0];
}

- (void)removeFromSuperview
{
  [_lifecycleManager unregisterAppLifecycleListener:self];
  [self stopSession];
  [super removeFromSuperview];
  [[NSNotificationCenter defaultCenter] removeObserver:self name:UIDeviceOrientationDidChangeNotification object:nil];
}

- (void)updateType
{
  UM_WEAKIFY(self);
  dispatch_async(_sessionQueue, ^{
    UM_ENSURE_STRONGIFY(self);
    [self initializeCaptureSessionInput];
    if (!self.session.isRunning) {
      [self startSession];
    }
  });
}

- (void)updateFlashMode
{
  AVCaptureDevice *device = [_videoCaptureDeviceInput device];
  NSError *error = nil;
  
  if (_flashMode == EXCameraFlashModeTorch) {
    if (![device hasTorch]) {
      return;
    }
    
    if (![device lockForConfiguration:&error]) {
      if (error) {
        UMLogInfo(@"%s: %@", __func__, error);
      }
      return;
    }
    
    if ([device hasTorch] && [device isTorchModeSupported:AVCaptureTorchModeOn]) {
      if ([device lockForConfiguration:&error]) {
        [device setTorchMode:AVCaptureTorchModeOn];
        [device unlockForConfiguration];
      } else {
        if (error) {
          UMLogInfo(@"%s: %@", __func__, error);
        }
      }
    }
  } else {
    if (![device hasFlash]) {
      return;
    }
    
    if (![device lockForConfiguration:&error]) {
      if (error) {
        UMLogInfo(@"%s: %@", __func__, error);
      }
      return;
    }

    if ([device hasFlash])
    {
      if ([device lockForConfiguration:&error]) {
        if ([device isTorchModeSupported:AVCaptureTorchModeOff]) {
          [device setTorchMode:AVCaptureTorchModeOff];
        }
        [device unlockForConfiguration];
      } else {
        if (error) {
          UMLogInfo(@"%s: %@", __func__, error);
        }
      }
    }
  }
  
  [device unlockForConfiguration];
}

- (void)updateFocusMode
{
  AVCaptureDevice *device = [_videoCaptureDeviceInput device];
  NSError *error = nil;
  
  if (![device lockForConfiguration:&error]) {
    if (error) {
      UMLogInfo(@"%s: %@", __func__, error);
    }
    return;
  }
  
  if ([device isFocusModeSupported:_autoFocus]) {
    if ([device lockForConfiguration:&error]) {
      [device setFocusMode:_autoFocus];
    } else {
      if (error) {
        UMLogInfo(@"%s: %@", __func__, error);
      }
    }
  }
  
  [device unlockForConfiguration];
}

- (void)updateFocusDepth
{
  AVCaptureDevice *device = [_videoCaptureDeviceInput device];
  NSError *error = nil;
  
  if (device == nil || device.focusMode != EXCameraAutoFocusOff) {
    return;
  }
  
  if ([device isLockingFocusWithCustomLensPositionSupported]) {
    if (![device lockForConfiguration:&error]) {
      if (error) {
        UMLogInfo(@"%s: %@", __func__, error);
      }
      return;
    }
    
    UM_WEAKIFY(device);
    [device setFocusModeLockedWithLensPosition:_focusDepth completionHandler:^(CMTime syncTime) {
      UM_ENSURE_STRONGIFY(device);
      [device unlockForConfiguration];
    }];
    return;
  }
  
  UMLogInfo(@"%s: Setting focusDepth isn't supported for this camera device", __func__);
  return;
}

- (void)updateZoom {
  AVCaptureDevice *device = [_videoCaptureDeviceInput device];
  NSError *error = nil;
  
  if (![device lockForConfiguration:&error]) {
    if (error) {
      UMLogInfo(@"%s: %@", __func__, error);
    }
    return;
  }
  
  device.videoZoomFactor = (device.activeFormat.videoMaxZoomFactor - 1.0) * _zoom + 1.0;
  
  [device unlockForConfiguration];
}

- (void)updateWhiteBalance
{
  AVCaptureDevice *device = [_videoCaptureDeviceInput device];
  NSError *error = nil;
  
  if (![device lockForConfiguration:&error]) {
    if (error) {
      UMLogInfo(@"%s: %@", __func__, error);
    }
    return;
  }
  
  if (_whiteBalance == EXCameraWhiteBalanceAuto) {
    [device setWhiteBalanceMode:AVCaptureWhiteBalanceModeContinuousAutoWhiteBalance];
    [device unlockForConfiguration];
  } else {
    AVCaptureWhiteBalanceTemperatureAndTintValues temperatureAndTint = {
      .temperature = [EXCameraUtils temperatureForWhiteBalance:_whiteBalance],
      .tint = 0,
    };
    AVCaptureWhiteBalanceGains rgbGains = [device deviceWhiteBalanceGainsForTemperatureAndTintValues:temperatureAndTint];
    if ([device lockForConfiguration:&error]) {
      UM_WEAKIFY(device);
      [device setWhiteBalanceModeLockedWithDeviceWhiteBalanceGains:rgbGains completionHandler:^(CMTime syncTime) {
        UM_ENSURE_STRONGIFY(device);
        [device unlockForConfiguration];
      }];
    } else {
      if (error) {
        UMLogInfo(@"%s: %@", __func__, error);
      }
    }
  }
  
  [device unlockForConfiguration];
}

- (void)updatePictureSize
{
  [self updateSessionPreset:_pictureSize];
}

- (void)setIsScanningBarCodes:(BOOL)barCodeScanning
{
  if (_barCodeScanner) {
    [_barCodeScanner setIsEnabled:barCodeScanning];
  }
}

- (void)setBarCodeScannerSettings:(NSDictionary *)settings
{
  if (_barCodeScanner) {
    [_barCodeScanner setSettings:settings];
  }
}

- (void)setIsDetectingFaces:(BOOL)faceDetecting
{
  if (_faceDetectorManager) {
    [_faceDetectorManager setIsEnabled:faceDetecting];
  }
}

- (void)updateFaceDetectorSettings:(NSDictionary *)settings
{
  if (_faceDetectorManager) {
    [_faceDetectorManager updateSettings:settings];
  }
}

- (void)takePicture:(NSDictionary *)options resolve:(UMPromiseResolveBlock)resolve reject:(UMPromiseRejectBlock)reject
{
  if (_photoCapturedResolve) {
    reject(@"E_ANOTHER_CAPTURE", @"Another photo capture is already being processed. Await the first call.", nil);
    return;
  }
  AVCaptureConnection *connection = [_photoOutput connectionWithMediaType:AVMediaTypeVideo];
  [connection setVideoOrientation:[EXCameraUtils videoOrientationForDeviceOrientation:[[UIDevice currentDevice] orientation]]];

  _photoCapturedReject = reject;
  _photoCapturedResolve = resolve;
  _photoCaptureOptions = options;

  AVCapturePhotoSettings *outputSettings = [AVCapturePhotoSettings photoSettingsWithFormat:@{AVVideoCodecKey : AVVideoCodecJPEG}];
  outputSettings.highResolutionPhotoEnabled = YES;
  AVCaptureFlashMode requestedFlashMode = AVCaptureFlashModeOff;
  switch (_flashMode) {
    case EXCameraFlashModeOff:
      requestedFlashMode = AVCaptureFlashModeOff;
      break;
    case EXCameraFlashModeAuto:
      requestedFlashMode = AVCaptureFlashModeAuto;
      break;
    case EXCameraFlashModeOn:
    case EXCameraFlashModeTorch:
      requestedFlashMode = AVCaptureFlashModeOn;
      break;
  }
  if ([[_photoOutput supportedFlashModes] containsObject:@(requestedFlashMode)]) {
    outputSettings.flashMode = requestedFlashMode;
  }
  [_photoOutput capturePhotoWithSettings:outputSettings delegate:self];
}

- (void)captureOutput:(AVCapturePhotoOutput *)output
didFinishProcessingPhotoSampleBuffer:(CMSampleBufferRef)photoSampleBuffer
previewPhotoSampleBuffer:(CMSampleBufferRef)previewPhotoSampleBuffer
     resolvedSettings:(AVCaptureResolvedPhotoSettings *)resolvedSettings
      bracketSettings:(AVCaptureBracketedStillImageSettings *)bracketSettings
                error:(NSError *)error
{
  NSDictionary *options = _photoCaptureOptions;
  UMPromiseRejectBlock reject = _photoCapturedReject;
  UMPromiseResolveBlock resolve = _photoCapturedResolve;
  _photoCapturedResolve = nil;
  _photoCapturedReject = nil;
  _photoCaptureOptions = nil;

  if (error || !photoSampleBuffer) {
    reject(@"E_IMAGE_CAPTURE_FAILED", @"Image could not be captured", error);
    return;
  }

  if (!self.fileSystem) {
    reject(@"E_IMAGE_CAPTURE_FAILED", @"No file system module", nil);
    return;
  }

  NSData *imageData = [AVCapturePhotoOutput JPEGPhotoDataRepresentationForJPEGSampleBuffer:photoSampleBuffer previewPhotoSampleBuffer:previewPhotoSampleBuffer];
  CFDictionaryRef exifAttachments = CMGetAttachment(photoSampleBuffer, kCGImagePropertyExifDictionary, NULL);
  NSDictionary *metadata = (__bridge NSDictionary *)exifAttachments;
  [self handleCapturedImageData:imageData exifMetadata:metadata options:options resolver:resolve];
}

- (void)captureOutput:(AVCapturePhotoOutput *)output didFinishProcessingPhoto:(AVCapturePhoto *)photo error:(NSError *)error API_AVAILABLE(ios(11.0))
{
  NSDictionary *options = _photoCaptureOptions;
  UMPromiseRejectBlock reject = _photoCapturedReject;
  UMPromiseResolveBlock resolve = _photoCapturedResolve;
  _photoCapturedResolve = nil;
  _photoCapturedReject = nil;
  _photoCaptureOptions = nil;

  if (error || !photo) {
    reject(@"E_IMAGE_CAPTURE_FAILED", @"Image could not be captured", error);
    return;
  }

  if (!self.fileSystem) {
    reject(@"E_IMAGE_CAPTURE_FAILED", @"No file system module", nil);
    return;
  }

  NSData *imageData = [photo fileDataRepresentation];
  [self handleCapturedImageData:imageData exifMetadata:photo.metadata[(NSString *)kCGImagePropertyExifDictionary] options:options resolver:resolve];
}

- (void)handleCapturedImageData:(NSData *)imageData exifMetadata:(NSDictionary *)exifMetadata options:(NSDictionary *)options resolver:(UMPromiseResolveBlock)resolve
{
  UIImage *takenImage = [UIImage imageWithData:imageData];
  BOOL useFastMode = [options[@"fastMode"] boolValue];
  if (useFastMode) {
    resolve(nil);
  }

  CGImageRef takenCGImage = takenImage.CGImage;

  CGSize previewSize;
  if (UIInterfaceOrientationIsPortrait([[UIApplication sharedApplication] statusBarOrientation])) {
    previewSize = CGSizeMake(self.previewLayer.frame.size.height, self.previewLayer.frame.size.width);
  } else {
    previewSize = CGSizeMake(self.previewLayer.frame.size.width, self.previewLayer.frame.size.height);
  }

  CGRect cropRect = CGRectMake(0, 0, CGImageGetWidth(takenCGImage), CGImageGetHeight(takenCGImage));
  CGRect croppedSize = AVMakeRectWithAspectRatioInsideRect(previewSize, cropRect);
  takenImage = [EXCameraUtils cropImage:takenImage toRect:croppedSize];

  float quality = [options[@"quality"] floatValue];
  NSData *takenImageData = UIImageJPEGRepresentation(takenImage, quality);

  NSString *path = [self.fileSystem generatePathInDirectory:[self.fileSystem.cachesDirectory stringByAppendingPathComponent:@"Camera"] withExtension:@".jpg"];

  NSMutableDictionary *response = [[NSMutableDictionary alloc] init];
  response[@"uri"] = [EXCameraUtils writeImage:takenImageData toPath:path];
  response[@"width"] = @(takenImage.size.width);
  response[@"height"] = @(takenImage.size.height);

  if ([options[@"base64"] boolValue]) {
    response[@"base64"] = [takenImageData base64EncodedStringWithOptions:0];
  }

  if ([options[@"exif"] boolValue]) {
    int imageRotation;
    switch (takenImage.imageOrientation) {
      case UIImageOrientationLeft:
        imageRotation = 90;
        break;
      case UIImageOrientationRight:
        imageRotation = -90;
        break;
      case UIImageOrientationDown:
        imageRotation = 180;
        break;
      default:
        imageRotation = 0;
    }
    [EXCameraUtils updateExifMetadata:exifMetadata withAdditionalData:@{ @"Orientation": @(imageRotation) } inResponse:response]; // TODO
  }

  if ([options[@"fastMode"] boolValue]) {
    [self onPictureSaved:@{@"data": response, @"id": options[@"id"]}];
  } else {
    resolve(response);
  }
}

- (void)record:(NSDictionary *)options resolve:(UMPromiseResolveBlock)resolve reject:(UMPromiseRejectBlock)reject
{
  if (_movieFileOutput == nil) {
    // At the time of writing AVCaptureMovieFileOutput and AVCaptureVideoDataOutput (> GMVDataOutput)
    // cannot coexist on the same AVSession (see: https://stackoverflow.com/a/4986032/1123156).
    // We stop face detection here and restart it in when AVCaptureMovieFileOutput finishes recording.
    if (_faceDetectorManager) {
      [_faceDetectorManager stopFaceDetection];
    }
    [self setupMovieFileCapture];
  }
  
  if (_movieFileOutput != nil && !_movieFileOutput.isRecording && _videoRecordedResolve == nil && _videoRecordedReject == nil) {
    if (options[@"maxDuration"]) {
      Float64 maxDuration = [options[@"maxDuration"] floatValue];
      _movieFileOutput.maxRecordedDuration = CMTimeMakeWithSeconds(maxDuration, 30);
    }
    
    if (options[@"maxFileSize"]) {
      _movieFileOutput.maxRecordedFileSize = [options[@"maxFileSize"] integerValue];
    }
    
    AVCaptureSessionPreset preset;
    if (options[@"quality"]) {
      EXCameraVideoResolution resolution = [options[@"quality"] integerValue];
      preset = [EXCameraUtils captureSessionPresetForVideoResolution:resolution];
    } else if ([_session.sessionPreset isEqual:AVCaptureSessionPresetPhoto]) {
      preset = AVCaptureSessionPresetHigh;
    }
    
    if (preset != nil) {
      [self updateSessionPreset:preset];
    }
    
    bool shouldBeMuted = options[@"mute"] && [options[@"mute"] boolValue];
    [self updateSessionAudioIsMuted:shouldBeMuted];
    
    AVCaptureConnection *connection = [_movieFileOutput connectionWithMediaType:AVMediaTypeVideo];
    // TODO: Add support for videoStabilizationMode (right now it is not only read, never written to)
    if (connection.isVideoStabilizationSupported == NO) {
      UMLogWarn(@"%s: Video Stabilization is not supported on this device.", __func__);
    } else {
      [connection setPreferredVideoStabilizationMode:self.videoStabilizationMode];
    }
    [connection setVideoOrientation:[EXCameraUtils videoOrientationForDeviceOrientation:[[UIDevice currentDevice] orientation]]];
    
    UM_WEAKIFY(self);
    dispatch_async(self.sessionQueue, ^{
      UM_STRONGIFY(self);
      if (!self) {
        reject(@"E_IMAGE_SAVE_FAILED", @"Camera view has been unmounted.", nil);
        return;
      }
      if (!self.fileSystem) {
        reject(@"E_IMAGE_SAVE_FAILED", @"No file system module", nil);
        return;
      }
      NSString *directory = [self.fileSystem.cachesDirectory stringByAppendingPathComponent:@"Camera"];
      NSString *path = [self.fileSystem generatePathInDirectory:directory withExtension:@".mov"];
      NSURL *outputURL = [[NSURL alloc] initFileURLWithPath:path];
      [self.movieFileOutput startRecordingToOutputFileURL:outputURL recordingDelegate:self];
      self.videoRecordedResolve = resolve;
      self.videoRecordedReject = reject;
    });
  }
}

- (void)maybeStartFaceDetection:(BOOL)mirrored {
  if (self.faceDetectorManager) {
    AVCaptureConnection *connection = [self.photoOutput connectionWithMediaType:AVMediaTypeVideo];
    [connection setVideoOrientation:[EXCameraUtils videoOrientationForDeviceOrientation:[[UIDevice currentDevice] orientation]]];
    [self.faceDetectorManager maybeStartFaceDetectionOnSession:self.session withPreviewLayer:self.previewLayer mirrored:mirrored];
  }
}

- (void)setPresetCamera:(NSInteger)presetCamera
{
  _presetCamera = presetCamera;
  [self.faceDetectorManager updateMirrored:_presetCamera!=1];
}

- (void)stopRecording
{
  [_movieFileOutput stopRecording];
}

- (void)resumePreview
{
  [[_previewLayer connection] setEnabled:YES];
}

- (void)pausePreview
{
  [[_previewLayer connection] setEnabled:NO];
}

- (void)startSession
{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunreachable-code"
#if TARGET_IPHONE_SIMULATOR
  return;
#endif
  NSDictionary *cameraPermissions = [_permissionsManager getPermissionsForResource:@"camera"];
  if (![cameraPermissions[@"status"] isEqualToString:@"granted"]) {
    [self onMountingError:@{@"message": @"Camera permissions not granted - component could not be rendered."}];
    return;
  }
  UM_WEAKIFY(self);
  dispatch_async(_sessionQueue, ^{
    UM_ENSURE_STRONGIFY(self);
    
    if (self.presetCamera == AVCaptureDevicePositionUnspecified) {
      return;
    }
    
    AVCapturePhotoOutput *photoOutput = [AVCapturePhotoOutput new];
    photoOutput.highResolutionCaptureEnabled = YES;
    photoOutput.livePhotoCaptureEnabled = NO;
    if ([self.session canAddOutput:photoOutput]) {
      [self.session addOutput:photoOutput];
      self.photoOutput = photoOutput;
    }
    
    [self setRuntimeErrorHandlingObserver:
     [[NSNotificationCenter defaultCenter] addObserverForName:AVCaptureSessionRuntimeErrorNotification object:self.session queue:nil usingBlock:^(NSNotification *note) {
      UM_ENSURE_STRONGIFY(self);
      dispatch_async(self.sessionQueue, ^{
        UM_ENSURE_STRONGIFY(self)
        // Manually restarting the session since it must
        // have been stopped due to an error.
        [self.session startRunning];
        [self onReady:nil];
      });
    }]];
    
    [self maybeStartFaceDetection:self.presetCamera!=1];
    if (self.barCodeScanner) {
      [self.barCodeScanner maybeStartBarCodeScanning];
    }
    
    [self.session startRunning];
    [self onReady:nil];
  });
#pragma clang diagnostic pop
}

- (void)stopSession
{
#if TARGET_IPHONE_SIMULATOR
  return;
#endif
  UM_WEAKIFY(self);
  dispatch_async(_sessionQueue, ^{
    UM_ENSURE_STRONGIFY(self);
    
    if (self.faceDetectorManager) {
      [self.faceDetectorManager stopFaceDetection];
    }
    if (self.barCodeScanner) {
      [self.barCodeScanner stopBarCodeScanning];
    }
    [self.previewLayer removeFromSuperlayer];
    [self.session commitConfiguration];
    [self.session stopRunning];
    for (AVCaptureInput *input in self.session.inputs) {
      [self.session removeInput:input];
    }
    
    for (AVCaptureOutput *output in self.session.outputs) {
      [self.session removeOutput:output];
    }
  });
}

- (void)initializeCaptureSessionInput
{
  if (_videoCaptureDeviceInput.device.position == _presetCamera) {
    return;
  }
  
  __block UIInterfaceOrientation interfaceOrientation;
  [UMUtilities performSynchronouslyOnMainThread:^{
    interfaceOrientation = [[UIApplication sharedApplication] statusBarOrientation];
  }];
  AVCaptureVideoOrientation orientation = [EXCameraUtils videoOrientationForInterfaceOrientation:interfaceOrientation];
  
  UM_WEAKIFY(self);
  dispatch_async(_sessionQueue, ^{
    UM_ENSURE_STRONGIFY(self);
    
    [self.session beginConfiguration];
    
    NSError *error = nil;
    AVCaptureDevice *captureDevice = [EXCameraUtils deviceWithMediaType:AVMediaTypeVideo preferringPosition:self.presetCamera];
    AVCaptureDeviceInput *captureDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:captureDevice error:&error];
    
    if (error || captureDeviceInput == nil) {
      NSString *errorMessage = @"Camera could not be started - ";
      if (error) {
        errorMessage = [errorMessage stringByAppendingString:[error description]];
      } else {
        errorMessage = [errorMessage stringByAppendingString:@"there's no captureDeviceInput available"];
      }
      [self onMountingError:@{@"message": errorMessage}];
      return;
    }
    
    [self.session removeInput:self.videoCaptureDeviceInput];
    if ([self.session canAddInput:captureDeviceInput]) {
      [self.session addInput:captureDeviceInput];
      
      self.videoCaptureDeviceInput = captureDeviceInput;
      [self updateFlashMode];
      [self updateZoom];
      [self updateFocusMode];
      [self updateFocusDepth];
      [self updateWhiteBalance];
      [self.previewLayer.connection setVideoOrientation:orientation];
    }
    
    [self.session commitConfiguration];
  });
}

#pragma mark - internal

- (void)updateSessionPreset:(AVCaptureSessionPreset)preset
{
#if !(TARGET_IPHONE_SIMULATOR)
  if (preset) {
    UM_WEAKIFY(self);
    dispatch_async(_sessionQueue, ^{
      UM_ENSURE_STRONGIFY(self);
      [self.session beginConfiguration];
      if ([self.session canSetSessionPreset:preset]) {
        self.session.sessionPreset = preset;
      }
      [self.session commitConfiguration];
    });
  }
#endif
}

- (void)updateSessionAudioIsMuted:(BOOL)isMuted
{
  UM_WEAKIFY(self);
  dispatch_async(_sessionQueue, ^{
    UM_ENSURE_STRONGIFY(self);
    [self.session beginConfiguration];
    
    for (AVCaptureDeviceInput* input in [self.session inputs]) {
      if ([input.device hasMediaType:AVMediaTypeAudio]) {
        if (isMuted) {
          [self.session removeInput:input];
        }
        [self.session commitConfiguration];
        return;
      }
    }
    
    if (!isMuted) {
      NSError *error = nil;
      
      AVCaptureDevice *audioCaptureDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
      AVCaptureDeviceInput *audioDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:audioCaptureDevice error:&error];
      
      if (error || audioDeviceInput == nil) {
        UMLogInfo(@"%s: %@", __func__, error);
        return;
      }
      
      if ([self.session canAddInput:audioDeviceInput]) {
        [self.session addInput:audioDeviceInput];
      }
    }
    
    [self.session commitConfiguration];
  });
}

- (void)onAppForegrounded
{
  if (![_session isRunning] && [self isSessionPaused]) {
    _paused = NO;
    UM_WEAKIFY(self);
    dispatch_async(_sessionQueue, ^{
      UM_ENSURE_STRONGIFY(self);
      [self.session startRunning];
    });
  }
}

- (void)onAppBackgrounded
{
  if ([_session isRunning] && ![self isSessionPaused]) {
    _paused = YES;
    UM_WEAKIFY(self);
    dispatch_async(_sessionQueue, ^{
      UM_ENSURE_STRONGIFY(self);
      [self.session stopRunning];
    });
  }
}

- (void)orientationChanged:(NSNotification *)notification
{
  UIInterfaceOrientation orientation = [[UIApplication sharedApplication] statusBarOrientation];
  [self changePreviewOrientation:orientation];
}

- (void)changePreviewOrientation:(UIInterfaceOrientation)orientation
{
  UM_WEAKIFY(self);
  AVCaptureVideoOrientation videoOrientation = [EXCameraUtils videoOrientationForInterfaceOrientation:orientation];
  [UMUtilities performSynchronouslyOnMainThread:^{
    UM_ENSURE_STRONGIFY(self);
    if (self.previewLayer.connection.isVideoOrientationSupported) {
      [self.previewLayer.connection setVideoOrientation:videoOrientation];
    }
  }];
}

# pragma mark - AVCaptureMovieFileOutput

- (void)setupMovieFileCapture
{
  AVCaptureMovieFileOutput *movieFileOutput = [[AVCaptureMovieFileOutput alloc] init];
  
  if ([_session canAddOutput:movieFileOutput]) {
    [_session addOutput:movieFileOutput];
    _movieFileOutput = movieFileOutput;
  }
}

- (void)cleanupMovieFileCapture
{
  if ([_session.outputs containsObject:_movieFileOutput]) {
    [_session removeOutput:_movieFileOutput];
    _movieFileOutput = nil;
  }
}

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput didFinishRecordingToOutputFileAtURL:(NSURL *)outputFileURL fromConnections:(NSArray *)connections error:(NSError *)error
{
  BOOL success = YES;
  if ([error code] != noErr) {
    NSNumber *value = [[error userInfo] objectForKey:AVErrorRecordingSuccessfullyFinishedKey];
    if (value) {
      success = [value boolValue];
    }
  }
  if (success && _videoRecordedResolve != nil) {
    _videoRecordedResolve(@{ @"uri": outputFileURL.absoluteString });
  } else if (_videoRecordedReject != nil) {
    _videoRecordedReject(@"E_RECORDING_FAILED", @"An error occurred while recording a video.", error);
  }
  _videoRecordedResolve = nil;
  _videoRecordedReject = nil;
  
  [self cleanupMovieFileCapture];
  // If face detection has been running prior to recording to file
  // we reenable it here (see comment in -record).
  [self maybeStartFaceDetection:false];
  
  if (_session.sessionPreset != _pictureSize) {
    [self updateSessionPreset:_pictureSize];
  }
}

# pragma mark - Face detector

- (id)createFaceDetectorManager
{
  id <UMFaceDetectorManagerProvider> faceDetectorProvider = [_moduleRegistry getModuleImplementingProtocol:@protocol(UMFaceDetectorManagerProvider)];
  
  if (faceDetectorProvider) {
    id <UMFaceDetectorManager> faceDetector = [faceDetectorProvider createFaceDetectorManager];
    if (faceDetector) {
      UM_WEAKIFY(self);
      [faceDetector setOnFacesDetected:^(NSArray<NSDictionary *> *faces) {
        UM_ENSURE_STRONGIFY(self);
        if (self.onFacesDetected) {
          self.onFacesDetected(@{
                                 @"type": @"face",
                                 @"faces": faces
                                 });
        }
      }];
      [faceDetector setSessionQueue:_sessionQueue];
    }
    return faceDetector;
  }
  return nil;
}

# pragma mark - BarCode scanner

- (id)createBarCodeScanner
{
  id<UMBarCodeScannerProviderInterface> barCodeScannerProvider = [_moduleRegistry getModuleImplementingProtocol:@protocol(UMBarCodeScannerProviderInterface)];
  if (barCodeScannerProvider) {
    id<UMBarCodeScannerInterface> barCodeScanner = [barCodeScannerProvider createBarCodeScanner];
    if (barCodeScanner) {
      UM_WEAKIFY(self);
      [barCodeScanner setSession:_session];
      [barCodeScanner setSessionQueue:_sessionQueue];
      [barCodeScanner setOnBarCodeScanned:^(NSDictionary *body) {
        UM_ENSURE_STRONGIFY(self);
        [self onBarCodeScanned:body];
      }];
    }
    return barCodeScanner;
  }
  return nil;
}

@end

