// Copyright 2016-present 650 Industries. All rights reserved.

#import <ABI34_0_0UMCore/ABI34_0_0UMModuleRegistry.h>

#import <ABI34_0_0EXFileSystem/ABI34_0_0EXDownloadDelegate.h>
#import <ABI34_0_0EXFileSystem/ABI34_0_0EXFileSystem.h>

#import <CommonCrypto/CommonDigest.h>

#import <ABI34_0_0EXFileSystem/ABI34_0_0EXFileSystemLocalFileHandler.h>
#import <ABI34_0_0EXFileSystem/ABI34_0_0EXFileSystemAssetLibraryHandler.h>

#import <ABI34_0_0UMFileSystemInterface/ABI34_0_0UMFileSystemInterface.h>
#import <ABI34_0_0UMFileSystemInterface/ABI34_0_0UMFilePermissionModuleInterface.h>


#import <ABI34_0_0UMCore/ABI34_0_0UMEventEmitterService.h>

NSString * const ABI34_0_0EXDownloadProgressEventName = @"Exponent.downloadProgress";

@interface ABI34_0_0EXDownloadResumable : NSObject

@property (nonatomic, strong) NSString *uuid;
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) ABI34_0_0EXDownloadDelegate *delegate;

@end

@implementation ABI34_0_0EXDownloadResumable

- (instancetype)initWithId:(NSString *)uuid
               withSession:(NSURLSession *)session
              withDelegate:(ABI34_0_0EXDownloadDelegate *)delegate;
{
  if ((self = [super init])) {
    _uuid = uuid;
    _session = session;
    _delegate = delegate;
  }
  return self;
}

@end

@interface ABI34_0_0EXFileSystem ()

@property (nonatomic, strong) NSMutableDictionary<NSString *, ABI34_0_0EXDownloadResumable*> *downloadObjects;
@property (nonatomic, weak) ABI34_0_0UMModuleRegistry *moduleRegistry;
@property (nonatomic, weak) id<ABI34_0_0UMEventEmitterService> eventEmitter;
@property (nonatomic, strong) NSString *documentDirectory;
@property (nonatomic, strong) NSString *cachesDirectory;
@property (nonatomic, strong) NSString *bundleDirectory;

@end

@implementation NSData (ABI34_0_0EXFileSystem)

- (NSString *)md5String
{
  unsigned char digest[CC_MD5_DIGEST_LENGTH];
  CC_MD5(self.bytes, (CC_LONG) self.length, digest);
  NSMutableString *md5 = [NSMutableString stringWithCapacity:2 * CC_MD5_DIGEST_LENGTH];
  for (unsigned int i = 0; i < CC_MD5_DIGEST_LENGTH; ++i) {
    [md5 appendFormat:@"%02x", digest[i]];
  }
  return md5;
}

@end

@implementation ABI34_0_0EXFileSystem

ABI34_0_0UM_REGISTER_MODULE();

+ (const NSString *)exportedModuleName
{
  return @"ExponentFileSystem";
}

+ (const NSArray<Protocol *> *)exportedInterfaces
{
  return @[@protocol(ABI34_0_0UMFileSystemInterface)];
}

- (instancetype)initWithDocumentDirectory:(NSString *)documentDirectory cachesDirectory:(NSString *)cachesDirectory bundleDirectory:(NSString *)bundleDirectory
{
  if (self = [super init]) {
    _documentDirectory = documentDirectory;
    _cachesDirectory = cachesDirectory;
    _bundleDirectory = bundleDirectory;
    _downloadObjects = [NSMutableDictionary dictionary];
    [ABI34_0_0EXFileSystem ensureDirExistsWithPath:_documentDirectory];
    [ABI34_0_0EXFileSystem ensureDirExistsWithPath:_cachesDirectory];
  }
  return self;
}

- (instancetype)init
{
  NSArray<NSString *> *documentPaths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
  NSString *documentDirectory = [documentPaths objectAtIndex:0];

  NSArray<NSString *> *cachesPaths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
  NSString *cacheDirectory = [cachesPaths objectAtIndex:0];

  return [self initWithDocumentDirectory:documentDirectory
                         cachesDirectory:cacheDirectory
                         bundleDirectory:[NSBundle mainBundle].bundlePath];
}

- (void)setModuleRegistry:(ABI34_0_0UMModuleRegistry *)moduleRegistry
{
  _moduleRegistry = moduleRegistry;
  _eventEmitter = [_moduleRegistry getModuleImplementingProtocol:@protocol(ABI34_0_0UMEventEmitterService)];
}

- (NSDictionary *)constantsToExport
{
  return @{
           @"documentDirectory": _documentDirectory ? [NSURL fileURLWithPath:_documentDirectory].absoluteString : [NSNull null],
           @"cacheDirectory": _cachesDirectory ? [NSURL fileURLWithPath:_cachesDirectory].absoluteString : [NSNull null],
           @"bundleDirectory": _bundleDirectory ? [NSURL fileURLWithPath:_bundleDirectory].absoluteString : [NSNull null]
           };
}

- (NSArray<NSString *> *)supportedEvents
{
  return @[ABI34_0_0EXDownloadProgressEventName];
}

- (void)startObserving {
  
}


- (void)stopObserving {
  
}

- (NSDictionary *)encodingMap
{
  /*
   TODO:Bacon: match node.js fs
   https://github.com/nodejs/node/blob/master/lib/buffer.js
   ascii
   base64
   binary
   hex
   ucs2/ucs-2
   utf16le/utf-16le
   utf8/utf-8
   latin1 (ISO8859-1, only in node 6.4.0+)
   */
  return @{
           @"ascii": @(NSASCIIStringEncoding),
           @"nextstep": @(NSNEXTSTEPStringEncoding),
           @"japaneseeuc": @(NSJapaneseEUCStringEncoding),
           @"utf8": @(NSUTF8StringEncoding),
           @"isolatin1": @(NSISOLatin1StringEncoding),
           @"symbol": @(NSSymbolStringEncoding),
           @"nonlossyascii": @(NSNonLossyASCIIStringEncoding),
           @"shiftjis": @(NSShiftJISStringEncoding),
           @"isolatin2": @(NSISOLatin2StringEncoding),
           @"unicode": @(NSUnicodeStringEncoding),
           @"windowscp1251": @(NSWindowsCP1251StringEncoding),
           @"windowscp1252": @(NSWindowsCP1252StringEncoding),
           @"windowscp1253": @(NSWindowsCP1253StringEncoding),
           @"windowscp1254": @(NSWindowsCP1254StringEncoding),
           @"windowscp1250": @(NSWindowsCP1250StringEncoding),
           @"iso2022jp": @(NSISO2022JPStringEncoding),
           @"macosroman": @(NSMacOSRomanStringEncoding),
           @"utf16": @(NSUTF16StringEncoding),
           @"utf16bigendian": @(NSUTF16BigEndianStringEncoding),
           @"utf16littleendian": @(NSUTF16LittleEndianStringEncoding),
           @"utf32": @(NSUTF32StringEncoding),
           @"utf32bigendian": @(NSUTF32BigEndianStringEncoding),
           @"utf32littleendian": @(NSUTF32LittleEndianStringEncoding),
           };
}

ABI34_0_0UM_EXPORT_METHOD_AS(getInfoAsync,
                    getInfoAsyncWithURI:(NSString *)uriString
                    withOptions:(NSDictionary *)options
                    resolver:(ABI34_0_0UMPromiseResolveBlock)resolve
                    rejecter:(ABI34_0_0UMPromiseRejectBlock)reject)
{
  NSURL *uri = [NSURL URLWithString:uriString];
  if (!([self permissionsForURI:uri] & ABI34_0_0UMFileSystemPermissionRead)) {
    reject(@"E_FILESYSTEM_PERMISSIONS",
           [NSString stringWithFormat:@"File '%@' isn't readable.", uri],
           nil);
    return;
  }
  
  if ([uri.scheme isEqualToString:@"file"]) {
    [ABI34_0_0EXFileSystemLocalFileHandler getInfoForFile:uri withOptions:options resolver:resolve rejecter:reject];
  } else if ([uri.scheme isEqualToString:@"assets-library"]) {
    [ABI34_0_0EXFileSystemAssetLibraryHandler getInfoForFile:uri withOptions:options resolver:resolve rejecter:reject];
  } else {
    reject(@"E_FILESYSTEM_INVALID_URI",
           [NSString stringWithFormat:@"Unsupported URI scheme for '%@'", uri],
           nil);
  }
}

ABI34_0_0UM_EXPORT_METHOD_AS(readAsStringAsync,
                    readAsStringAsyncWithURI:(NSString *)uriString
                    withOptions:(NSDictionary *)options
                    resolver:(ABI34_0_0UMPromiseResolveBlock)resolve
                    rejecter:(ABI34_0_0UMPromiseRejectBlock)reject)
{
  NSURL *uri = [NSURL URLWithString:uriString];
  if (!([self permissionsForURI:uri] & ABI34_0_0UMFileSystemPermissionRead)) {
    reject(@"E_FILESYSTEM_PERMISSIONS",
           [NSString stringWithFormat:@"File '%@' isn't readable.", uri],
           nil);
    return;
  }
  
  if ([uri.scheme isEqualToString:@"file"]) {
    NSString *encodingType = @"utf8";
    if (options[@"encoding"] && [options[@"encoding"] isKindOfClass:[NSString class]]) {
      encodingType = [options[@"encoding"] lowercaseString];
    }
    if ([encodingType isEqualToString:@"base64"]) {
      NSFileHandle *file = [NSFileHandle fileHandleForReadingAtPath:uri.path];
      if (file == nil) {
        reject(@"E_FILE_NOT_READ",
               [NSString stringWithFormat:@"File '%@' could not be read.", uri.path],
               nil);
        return;
      }
      // position and length are used as a cursor/paging system.
      if ([options[@"position"] isKindOfClass:[NSNumber class]]) {
        [file seekToFileOffset:[options[@"position"] intValue]];
      }
      
      NSData *data;
      if ([options[@"length"] isKindOfClass:[NSNumber class]]) {
        data = [file readDataOfLength:[options[@"length"] intValue]];
      } else {
        data = [file readDataToEndOfFile];
      }
      resolve([data base64EncodedStringWithOptions:NSDataBase64EncodingEndLineWithLineFeed]);
    } else {
      NSUInteger encoding = NSUTF8StringEncoding;
      id possibleEncoding = [[self encodingMap] valueForKey:encodingType];
      if (possibleEncoding != nil) {
        encoding = [possibleEncoding integerValue];
      }
      NSError *error;
      NSString *string = [NSString stringWithContentsOfFile:uri.path encoding:encoding error:&error];
      if (string) {
        resolve(string);
      } else {
        reject(@"E_FILE_NOT_READ",
               [NSString stringWithFormat:@"File '%@' could not be read.", uri],
               error);
      }
    }
  } else {
    reject(@"E_FILESYSTEM_INVALID_URI",
           [NSString stringWithFormat:@"Unsupported URI scheme for '%@'", uri],
           nil);
  }
}

ABI34_0_0UM_EXPORT_METHOD_AS(writeAsStringAsync,
                    writeAsStringAsyncWithURI:(NSString *)uriString
                    withString:(NSString *)string
                    withOptions:(NSDictionary *)options
                    resolver:(ABI34_0_0UMPromiseResolveBlock)resolve
                    rejecter:(ABI34_0_0UMPromiseRejectBlock)reject)
{
  NSURL *uri = [NSURL URLWithString:uriString];
  if (!([self permissionsForURI:uri] & ABI34_0_0UMFileSystemPermissionWrite)) {
    reject(@"E_FILESYSTEM_PERMISSIONS",
           [NSString stringWithFormat:@"File '%@' isn't writable.", uri],
           nil);
    return;
  }
  
  if ([uri.scheme isEqualToString:@"file"]) {
    NSString *encodingType = @"utf8";
    if ([options[@"encoding"] isKindOfClass:[NSString class]]) {
      encodingType = [options[@"encoding"] lowercaseString];
    }
    if ([encodingType isEqualToString:@"base64"]) {
      dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSData *imageData = [[NSData alloc] initWithBase64EncodedString:string options:NSDataBase64DecodingIgnoreUnknownCharacters];
        if (imageData) {
          // TODO:Bacon: Should we surface `attributes`?
          if ([[NSFileManager defaultManager] createFileAtPath:uri.path contents:imageData attributes:nil]) {
            resolve([NSNull null]);
          } else {
            return reject(@"E_FILE_UNKNOWN",
                          [NSString stringWithFormat:@"No such file or directory '%@'", uri.path],
                          nil);
          }
        } else {
          reject(@"E_INVALID_FORMAT",
                 @"Failed to parse base64 string.",
                 nil);
        }
      });
    } else {
      NSUInteger encoding = NSUTF8StringEncoding;
      id possibleEncoding = [[self encodingMap] valueForKey:encodingType];
      if (possibleEncoding != nil) {
        encoding = [possibleEncoding integerValue];
      }
      
      NSError *error;
      if ([string writeToFile:uri.path atomically:YES encoding:encoding error:&error]) {
        resolve([NSNull null]);
      } else {
        reject(@"E_FILE_NOT_WRITTEN",
               [NSString stringWithFormat:@"File '%@' could not be written.", uri],
               error);
      }
    }
  } else {
    reject(@"E_FILESYSTEM_INVALID_URI",
           [NSString stringWithFormat:@"Unsupported URI scheme for '%@'", uri],
           nil);
  }
}

ABI34_0_0UM_EXPORT_METHOD_AS(deleteAsync,
                    deleteAsyncWithURI:(NSString *)uriString
                    withOptions:(NSDictionary *)options
                    resolver:(ABI34_0_0UMPromiseResolveBlock)resolve
                    rejecter:(ABI34_0_0UMPromiseRejectBlock)reject)
{
  NSURL *uri = [NSURL URLWithString:uriString];
  if (!([self permissionsForURI:[uri URLByAppendingPathComponent:@".."]] & ABI34_0_0UMFileSystemPermissionWrite)) {
    reject(@"E_FILESYSTEM_PERMISSIONS",
           [NSString stringWithFormat:@"Location '%@' isn't deletable.", uri],
           nil);
    return;
  }
  
  if ([uri.scheme isEqualToString:@"file"]) {
    NSString *path = uri.path;
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
      NSError *error;
      if ([[NSFileManager defaultManager] removeItemAtPath:path error:&error]) {
        resolve([NSNull null]);
      } else {
        reject(@"E_FILE_NOT_DELETED",
               [NSString stringWithFormat:@"File '%@' could not be deleted.", uri],
               error);
      }
    } else {
      if (options[@"idempotent"]) {
        resolve([NSNull null]);
      } else {
        reject(@"E_FILE_NOT_FOUND",
               [NSString stringWithFormat:@"File '%@' could not be deleted because it could not be found.", uri],
               nil);
      }
    }
  } else {
    reject(@"E_FILESYSTEM_INVALID_URI",
           [NSString stringWithFormat:@"Unsupported URI scheme for '%@'", uri],
           nil);
  }
}

ABI34_0_0UM_EXPORT_METHOD_AS(moveAsync,
                    moveAsyncWithOptions:(NSDictionary *)options
                    resolver:(ABI34_0_0UMPromiseResolveBlock)resolve
                    rejecter:(ABI34_0_0UMPromiseRejectBlock)reject)
{
  NSURL *from = [NSURL URLWithString:options[@"from"]];
  if (!from) {
    reject(@"E_MISSING_PARAMETER", @"Need a `from` location.", nil);
    return;
  }
  if (!([self permissionsForURI:[from URLByAppendingPathComponent:@".."]] & ABI34_0_0UMFileSystemPermissionWrite)) {
    reject(@"E_FILESYSTEM_PERMISSIONS",
           [NSString stringWithFormat:@"Location '%@' isn't movable.", from],
           nil);
    return;
  }
  NSURL *to = [NSURL URLWithString:options[@"to"]];
  if (!to) {
    reject(@"E_MISSING_PARAMETER", @"Need a `to` location.", nil);
    return;
  }
  if (!([self permissionsForURI:to] & ABI34_0_0UMFileSystemPermissionWrite)) {
    reject(@"E_FILESYSTEM_PERMISSIONS",
           [NSString stringWithFormat:@"File '%@' isn't writable.", to],
           nil);
    return;
  }
  
  // NOTE: The destination-delete and the move should happen atomically, but we hope for the best for now
  if ([from.scheme isEqualToString:@"file"]) {
    NSString *fromPath = [from.path stringByStandardizingPath];
    NSString *toPath = [to.path stringByStandardizingPath];
    NSError *error;
    if ([[NSFileManager defaultManager] fileExistsAtPath:toPath]) {
      if (![[NSFileManager defaultManager] removeItemAtPath:toPath error:&error]) {
        reject(@"E_FILE_NOT_MOVED",
               [NSString stringWithFormat:@"File '%@' could not be moved to '%@' because a file already exists at "
                "the destination and could not be deleted.", from, to],
               error);
        return;
      }
    }
    if ([[NSFileManager defaultManager] moveItemAtPath:fromPath toPath:toPath error:&error]) {
      resolve([NSNull null]);
    } else {
      reject(@"E_FILE_NOT_MOVED",
             [NSString stringWithFormat:@"File '%@' could not be moved to '%@'.", from, to],
             error);
    }
  } else {
    reject(@"E_FILESYSTEM_INVALID_URI",
           [NSString stringWithFormat:@"Unsupported URI scheme for '%@'", from],
           nil);
  }
}

ABI34_0_0UM_EXPORT_METHOD_AS(copyAsync,
                    copyAsyncWithOptions:(NSDictionary *)options
                    resolver:(ABI34_0_0UMPromiseResolveBlock)resolve
                    rejecter:(ABI34_0_0UMPromiseRejectBlock)reject)
{
  NSURL *from = [NSURL URLWithString:options[@"from"]];
  if (!from) {
    reject(@"E_MISSING_PARAMETER", @"Need a `from` location.", nil);
    return;
  }
  if (!([self permissionsForURI:from] & ABI34_0_0UMFileSystemPermissionRead)) {
    reject(@"E_FILESYSTEM_PERMISSIONS",
           [NSString stringWithFormat:@"File '%@' isn't readable.", from],
           nil);
    return;
  }
  NSURL *to = [NSURL URLWithString:options[@"to"]];
  if (!to) {
    reject(@"E_MISSING_PARAMETER", @"Need a `to` location.", nil);
    return;
  }
  if (!([self permissionsForURI:to] & ABI34_0_0UMFileSystemPermissionWrite)) {
    reject(@"E_FILESYSTEM_PERMISSIONS",
           [NSString stringWithFormat:@"File '%@' isn't writable.", to],
           nil);
    return;
  }
  
  if ([from.scheme isEqualToString:@"file"]) {
    [ABI34_0_0EXFileSystemLocalFileHandler copyFrom:from to:to resolver:resolve rejecter:reject];
  } else if ([from.scheme isEqualToString:@"assets-library"]) {
    [ABI34_0_0EXFileSystemAssetLibraryHandler copyFrom:from to:to resolver:resolve rejecter:reject];
  } else {
    reject(@"E_FILESYSTEM_INVALID_URI",
           [NSString stringWithFormat:@"Unsupported URI scheme for '%@'", from],
           nil);
  }
}

ABI34_0_0UM_EXPORT_METHOD_AS(makeDirectoryAsync,
                    makeDirectoryAsyncWithURI:(NSString *)uriString
                    withOptions:(NSDictionary *)options
                    resolver:(ABI34_0_0UMPromiseResolveBlock)resolve
                    rejecter:(ABI34_0_0UMPromiseRejectBlock)reject)
{
  
  NSURL *uri = [NSURL URLWithString:uriString];
  if (!([self permissionsForURI:uri] & ABI34_0_0UMFileSystemPermissionWrite)) {
    reject(@"E_FILESYSTEM_PERMISSIONS",
           [NSString stringWithFormat:@"Directory '%@' could not be created because the location isn't writable.", uri],
           nil);
    return;
  }
  
  if ([uri.scheme isEqualToString:@"file"]) {
    NSError *error;
    if ([[NSFileManager defaultManager] createDirectoryAtPath:uri.path
                                  withIntermediateDirectories:[options[@"intermediates"] boolValue]
                                                   attributes:nil
                                                        error:&error]) {
      resolve([NSNull null]);
    } else {
      reject(@"E_DIRECTORY_NOT_CREATED",
             [NSString stringWithFormat:@"Directory '%@' could not be created.", uri],
             error);
    }
  } else {
    reject(@"E_FILESYSTEM_INVALID_URI",
           [NSString stringWithFormat:@"Unsupported URI scheme for '%@'", uri],
           nil);
  }
}

ABI34_0_0UM_EXPORT_METHOD_AS(readDirectoryAsync,
                    readDirectoryAsyncWithURI:(NSString *)uriString
                    withOptions:(NSDictionary *)options
                    resolver:(ABI34_0_0UMPromiseResolveBlock)resolve
                    rejecter:(ABI34_0_0UMPromiseRejectBlock)reject)
{
  NSURL *uri = [NSURL URLWithString:uriString];
  if (!([self permissionsForURI:uri] & ABI34_0_0UMFileSystemPermissionRead)) {
    reject(@"E_FILESYSTEM_PERMISSIONS",
           [NSString stringWithFormat:@"Location '%@' isn't readable.", uri],
           nil);
    return;
  }
  
  if ([uri.scheme isEqualToString:@"file"]) {
    NSError *error;
    NSArray<NSString *> *children = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:uri.path error:&error];
    if (children) {
      resolve(children);
    } else {
      reject(@"E_DIRECTORY_NOT_READ",
             [NSString stringWithFormat:@"Directory '%@' could not be read.", uri],
             error);
    }
  } else {
    reject(@"E_FILESYSTEM_INVALID_URI",
           [NSString stringWithFormat:@"Unsupported URI scheme for '%@'", uri],
           nil);
  }
}

ABI34_0_0UM_EXPORT_METHOD_AS(downloadAsync,
                    downloadAsyncWithUrl:(NSString *)uriString
                    withLocalURI:(NSString *)localUriString
                    withOptions:(NSDictionary *)options
                    resolver:(ABI34_0_0UMPromiseResolveBlock)resolve
                    rejecter:(ABI34_0_0UMPromiseRejectBlock)reject)
{
  NSURL *url = [NSURL URLWithString:uriString];
  NSURL *localUri = [NSURL URLWithString:localUriString];
  if (!([self checkIfFileDirExists:localUri.path])) {
    reject(@"E_FILESYSTEM_WRONG_DESTINATION",
           [NSString stringWithFormat:@"Directory for %@ doesn't exist.", localUriString],
           nil);
    return;
  }
  if (!([self permissionsForURI:localUri] & ABI34_0_0UMFileSystemPermissionWrite)) {
    reject(@"E_FILESYSTEM_PERMISSIONS",
           [NSString stringWithFormat:@"File '%@' isn't writable.", localUri],
           nil);
    return;
  }
  NSString *path = localUri.path;
  
  NSURLSessionConfiguration *sessionConfiguration = [NSURLSessionConfiguration defaultSessionConfiguration];
  sessionConfiguration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
  NSDictionary *headerDict = (NSDictionary *) [options objectForKey:@"headers"];
  if (headerDict != nil) {
    sessionConfiguration.HTTPAdditionalHeaders = headerDict;
  }
  sessionConfiguration.URLCache = nil;
  NSURLSession *session = [NSURLSession sessionWithConfiguration:sessionConfiguration];
  NSURLSessionDataTask *task = [session dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
    if (error) {
      reject(@"E_DOWNLOAD_FAILED",
             [NSString stringWithFormat:@"Could not download from '%@'", url],
             error);
      return;
    }
    [data writeToFile:path atomically:YES];
    
    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    result[@"uri"] = [NSURL fileURLWithPath:path].absoluteString;
    if (options[@"md5"]) {
      result[@"md5"] = [data md5String];
    }
    result[@"status"] = @([httpResponse statusCode]);
    result[@"headers"] = [httpResponse allHeaderFields];
    resolve(result);
  }];
  [task resume];
}

ABI34_0_0UM_EXPORT_METHOD_AS(downloadResumableStartAsync,
                    downloadResumableStartAsyncWithUrl:(NSString *)urlString
                    withFileURI:(NSString *)fileUri
                    withUUID:(NSString *)uuid
                    withOptions:(NSDictionary *)options
                    withResumeData:(NSString *)data
                    resolver:(ABI34_0_0UMPromiseResolveBlock)resolve
                    rejecter:(ABI34_0_0UMPromiseRejectBlock)reject)
{
  NSURL *url = [NSURL URLWithString:urlString];
  NSURL *localUrl = [NSURL URLWithString:fileUri];
  if (!([self checkIfFileDirExists:localUrl.path])) {
    reject(@"E_FILESYSTEM_WRONG_DESTINATION",
           [NSString stringWithFormat:@"Directory for %@ doesn't exist.", fileUri],
           nil);
    return;
  }
  if (![localUrl.scheme isEqualToString:@"file"]) {
    reject(@"E_FILESYSTEM_PERMISSIONS",
           [NSString stringWithFormat:@"Cannot download to '%@': only 'file://' URI destinations are supported.", fileUri],
           nil);
    return;
  }
  
  NSString *path = localUrl.path;
  if (!([self _permissionsForPath:path] & ABI34_0_0UMFileSystemPermissionWrite)) {
    reject(@"E_FILESYSTEM_PERMISSIONS",
           [NSString stringWithFormat:@"File '%@' isn't writable.", fileUri],
           nil);
    return;
  }
  NSData *resumeData = data ? [[NSData alloc] initWithBase64EncodedString:data options:0] : nil;
  [self _downloadResumableCreateSessionWithUrl:url
                                withScopedPath:path
                                      withUUID:uuid
                                   withOptions:options
                                withResumeData:resumeData
                                  withResolver:resolve
                                  withRejecter:reject];
}

ABI34_0_0UM_EXPORT_METHOD_AS(downloadResumablePauseAsync,
                    downloadResumablePauseAsyncWithUUID:(NSString *)uuid
                    resolver:(ABI34_0_0UMPromiseResolveBlock)resolve
                    rejecter:(ABI34_0_0UMPromiseRejectBlock)reject)
{
  ABI34_0_0EXDownloadResumable *downloadResumable = (ABI34_0_0EXDownloadResumable *)self.downloadObjects[uuid];
  if (downloadResumable == nil) {
    reject(@"E_UNABLE_TO_PAUSE",
           [NSString stringWithFormat:@"There is no download object with UUID: %@", uuid],
           nil);
  } else {
    [downloadResumable.session getTasksWithCompletionHandler:^(NSArray<NSURLSessionDataTask *> * _Nonnull dataTasks, NSArray<NSURLSessionUploadTask *> * _Nonnull uploadTasks, NSArray<NSURLSessionDownloadTask *> * _Nonnull downloadTasks) {
      NSURLSessionDownloadTask *downloadTask = [downloadTasks firstObject];
      if (downloadTask) {
        [downloadTask cancelByProducingResumeData:^(NSData * _Nullable resumeData) {
          resolve(@{ @"resumeData": ABI34_0_0UMNullIfNil([resumeData base64EncodedStringWithOptions:0]) });
        }];
      } else {
        reject(@"E_UNABLE_TO_PAUSE",
               @"There was an error producing resume data",
               nil);
      }
    }];
  }
}

#pragma mark - Internal methods

- (void)_downloadResumableCreateSessionWithUrl:(NSURL *)url withScopedPath:(NSString *)scopedPath withUUID:(NSString *)uuid withOptions:(NSDictionary *)options withResumeData:(NSData * _Nullable)resumeData withResolver:(ABI34_0_0UMPromiseResolveBlock)resolve withRejecter:(ABI34_0_0UMPromiseRejectBlock)reject
{
  NSURLSessionConfiguration *sessionConfiguration = [NSURLSessionConfiguration defaultSessionConfiguration];
  sessionConfiguration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
  sessionConfiguration.URLCache = nil;
  
  __weak typeof(self) weakSelf = self;
  ABI34_0_0EXDownloadDelegateOnWriteCallback onWrite = ^(NSURLSessionDownloadTask *task, int64_t bytesWritten, int64_t totalBytesWritten, int64_t totalBytesExpectedToWrite) {
    __strong ABI34_0_0EXFileSystem *strongSelf = weakSelf;
    if (strongSelf && bytesWritten > 0) {
      [strongSelf sendEventWithName:ABI34_0_0EXDownloadProgressEventName
                               body:@{@"uuid":uuid,
                                      @"data":@{
                                          @"totalBytesWritten": @(totalBytesWritten),
                                          @"totalBytesExpectedToWrite": @(totalBytesExpectedToWrite),
                                          },
                                      }];
    }
  };
  
  ABI34_0_0EXDownloadDelegateOnDownloadCallback onDownload = ^(NSURLSessionDownloadTask *task, NSURL *location) {
    NSURL *scopedLocation = [NSURL fileURLWithPath:scopedPath];
    NSData *locationData = [NSData dataWithContentsOfURL:location];
    [locationData writeToFile:scopedPath atomically:YES];
    NSData *data = [NSData dataWithContentsOfURL:scopedLocation];
    if (!data) {
      reject(@"E_UNABLE_TO_SAVE",
             @"Unable to save file to local URI",
             nil);
      return;
    }
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    result[@"uri"] = scopedLocation.absoluteString;
    result[@"complete"] = @(YES);
    if (options[@"md5"]) {
      result[@"md5"] = [data md5String];
    }
    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)task.response;
    result[@"status"] = @([httpResponse statusCode]);
    result[@"headers"] = [httpResponse allHeaderFields];
    
    __strong ABI34_0_0EXFileSystem *strongSelf = weakSelf;
    if (strongSelf) {
      [strongSelf.downloadObjects removeObjectForKey:uuid];
    }
    
    resolve(result);
  };
  
  ABI34_0_0EXDownloadDelegateOnErrorCallback onError = ^(NSError *error) {
    //"cancelled" description when paused.  Don't throw.
    if ([error.localizedDescription isEqualToString:@"cancelled"]) {
      __strong ABI34_0_0EXFileSystem *strongSelf = weakSelf;
      if (strongSelf) {
        [strongSelf.downloadObjects removeObjectForKey:uuid];
      }
      resolve([NSNull null]);
    } else {
      reject(@"E_UNABLE_TO_DOWNLOAD",
             [NSString stringWithFormat:@"Unable to download from: %@", url.absoluteString],
             error);
    }
  };
  
  
  ABI34_0_0EXDownloadDelegate *downloadDelegate = [[ABI34_0_0EXDownloadDelegate alloc] initWithId:uuid
                                                                        onWrite:onWrite
                                                                     onDownload:onDownload
                                                                        onError:onError];
  
  NSURLSession *session = [NSURLSession sessionWithConfiguration:sessionConfiguration
                                                        delegate:downloadDelegate
                                                   delegateQueue:[NSOperationQueue mainQueue]];
  
  ABI34_0_0EXDownloadResumable *downloadResumable = [[ABI34_0_0EXDownloadResumable alloc] initWithId:uuid
                                                                       withSession:session
                                                                      withDelegate:downloadDelegate];
  self.downloadObjects[downloadResumable.uuid] = downloadResumable;
  
  NSURLSessionDownloadTask *downloadTask;
  if (resumeData) {
    downloadTask = [session downloadTaskWithResumeData:resumeData];
  } else {
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url];
    if (options[@"headers"]) {
      NSDictionary *headerDict = (NSDictionary *) [options objectForKey:@"headers"];
      for (NSString *key in headerDict) {
        NSString *value = (NSString *) [headerDict objectForKey:key];
        [request addValue:value forHTTPHeaderField:key];
      }
    }
    downloadTask = [session downloadTaskWithRequest:request];
  }
  [downloadTask resume];
}

- (ABI34_0_0UMFileSystemPermissionFlags)_permissionsForPath:(NSString *)path
{
  return [[_moduleRegistry getModuleImplementingProtocol:@protocol(ABI34_0_0UMFilePermissionModuleInterface)] getPathPermissions:(NSString *)path];
}

- (void)sendEventWithName:(NSString *)eventName body:(id)body
{
  if (_eventEmitter != nil) {
    [_eventEmitter sendEventWithName:eventName body:body];
  }
}

#pragma mark - Public utils

- (ABI34_0_0UMFileSystemPermissionFlags)permissionsForURI:(NSURL *)uri
{
  NSArray *validSchemas = @[
                            @"assets-library",
                            @"http",
                            @"https",
                            ];
  if ([validSchemas containsObject:uri.scheme]) {
    return ABI34_0_0UMFileSystemPermissionRead;
  }
  if ([uri.scheme isEqualToString:@"file"]) {
    return [self _permissionsForPath:uri.path];
  }
  return ABI34_0_0UMFileSystemPermissionNone;
}

- (BOOL)checkIfFileDirExists:(NSString *)path
{
  NSString *dir = [path stringByDeletingLastPathComponent];
  return [[NSFileManager defaultManager] fileExistsAtPath:dir];
}

#pragma mark - Class methods

- (BOOL)ensureDirExistsWithPath:(NSString *)path
{
  return [ABI34_0_0EXFileSystem ensureDirExistsWithPath:path];
}

+ (BOOL)ensureDirExistsWithPath:(NSString *)path
{
  BOOL isDir = NO;
  NSError *error;
  BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir];
  if (!(exists && isDir)) {
    [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:&error];
    if (error) {
      return NO;
    }
  }
  return YES;
}

- (NSString *)generatePathInDirectory:(NSString *)directory withExtension:(NSString *)extension
{
  return [ABI34_0_0EXFileSystem generatePathInDirectory:directory withExtension:extension];
}


+ (NSString *)generatePathInDirectory:(NSString *)directory withExtension:(NSString *)extension
{
  NSString *fileName = [[[NSUUID UUID] UUIDString] stringByAppendingString:extension];
  [ABI34_0_0EXFileSystem ensureDirExistsWithPath:directory];
  return [directory stringByAppendingPathComponent:fileName];
}

@end
