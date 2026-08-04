// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

@import video_player_cf;
@import XCTest;

#import <OCMock/OCMock.h>
#import <objc/runtime.h>

#import <video_player_cf/VICacheConfiguration.h>
#import <video_player_cf/VIContentInfo.h>
#import <video_player_cf/VIMediaCacheWorker.h>
#import <video_player_cf/VIMediaDownloader.h>

@interface TestCacheWorker : VIMediaCacheWorker

@property(nonatomic, strong) VICacheConfiguration *testCacheConfiguration;
@property(nonatomic, copy) NSArray *testActions;

@end

@implementation TestCacheWorker

- (instancetype)init {
  self = [super init];
  if (self) {
    NSString *filePath = [NSTemporaryDirectory()
        stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    _testCacheConfiguration =
        [VICacheConfiguration configurationWithFilePath:filePath];
    VIContentInfo *contentInfo = [[VIContentInfo alloc] init];
    contentInfo.contentLength = 1024;
    _testCacheConfiguration.contentInfo = contentInfo;
    _testActions = @[];
  }
  return self;
}

- (VICacheConfiguration *)cacheConfiguration {
  return self.testCacheConfiguration;
}

- (NSArray *)cachedDataActionsForRange:(NSRange)range {
  return self.testActions;
}

@end

static NSInteger gActionWorkerCancelCount = 0;
static void *kDidCountCancelKey = &kDidCountCancelKey;

static void TestActionWorkerStartNoOp(id self, SEL _cmd) {
}

static void TestActionWorkerCancelNoOp(id self, SEL _cmd) {
  if (objc_getAssociatedObject(self, kDidCountCancelKey)) {
    return;
  }
  objc_setAssociatedObject(self, kDidCountCancelKey, @YES,
                           OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  gActionWorkerCancelCount += 1;
}

static IMP SwapMethodImplementation(Class cls, SEL selector, IMP replacement) {
  Method method = class_getInstanceMethod(cls, selector);
  IMP original = method_getImplementation(method);
  method_setImplementation(method, replacement);
  return original;
}

@interface VideoPlayerTests : XCTestCase
@end

@implementation VideoPlayerTests

- (void)testPlugin {
  CFLTVideoPlayerPlugin *plugin = [[CFLTVideoPlayerPlugin alloc] init];
  XCTAssertNotNil(plugin);
}

- (void)testSeekToInvokesTextureFrameAvailableOnTextureRegistry {
  NSObject<FlutterTextureRegistry> *mockTextureRegistry =
      OCMProtocolMock(@protocol(FlutterTextureRegistry));
  NSObject<FlutterPluginRegistry> *registry =
      (NSObject<FlutterPluginRegistry> *)[[UIApplication sharedApplication] delegate];
  NSObject<FlutterPluginRegistrar> *registrar =
      [registry registrarForPlugin:@"TEST_CFLTVideoPlayerPlugin"];
  NSObject<FlutterPluginRegistrar> *partialRegistrar = OCMPartialMock(registrar);
  OCMStub([partialRegistrar textures]).andReturn(mockTextureRegistry);
  [CFLTVideoPlayerPlugin registerWithRegistrar:partialRegistrar];
  CFLTVideoPlayerPlugin<CFLTVideoPlayerApi> *videoPlayerPlugin =
      (CFLTVideoPlayerPlugin<CFLTVideoPlayerApi> *)[[CFLTVideoPlayerPlugin alloc]
          initWithRegistrar:partialRegistrar];
  CFLTPositionMessage *message = [[CFLTPositionMessage alloc] init];
  message.textureId = @101;
  message.position = @0;
  FlutterError *error;
  [videoPlayerPlugin seekTo:message error:&error];
  OCMVerify([mockTextureRegistry textureFrameAvailable:message.textureId.intValue]);
}

- (void)testCacheConfigurationKeepsStableBackingCollections {
  NSString *filePath = [NSTemporaryDirectory()
      stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
  VICacheConfiguration *configuration =
      [VICacheConfiguration configurationWithFilePath:filePath];

  id initialFragments = [configuration valueForKey:@"internalCacheFragments"];
  id initialDownloadInfo = [configuration valueForKey:@"downloadInfo"];

  [configuration addCacheFragment:NSMakeRange(0, 64)];
  [configuration addDownloadedBytes:256 spent:0.25];

  XCTAssertEqual(initialFragments,
                 [configuration valueForKey:@"internalCacheFragments"]);
  XCTAssertEqual(initialDownloadInfo,
                 [configuration valueForKey:@"downloadInfo"]);
}

- (void)testDownloadTaskReplacementCancelsPreviousWorker {
  Class actionWorkerClass = NSClassFromString(@"VIActionWorker");
  XCTAssertNotNil(actionWorkerClass);

  IMP originalStart =
      SwapMethodImplementation(actionWorkerClass, @selector(start),
                               (IMP)TestActionWorkerStartNoOp);
  IMP originalCancel =
      SwapMethodImplementation(actionWorkerClass, @selector(cancel),
                               (IMP)TestActionWorkerCancelNoOp);

  gActionWorkerCancelCount = 0;

  @try {
    TestCacheWorker *cacheWorker = [[TestCacheWorker alloc] init];
    VIMediaDownloader *downloader =
        [[VIMediaDownloader alloc] initWithURL:[NSURL URLWithString:@"https://example.com/video.mp4"]
                                   cacheWorker:cacheWorker];

    [downloader downloadTaskFromOffset:0 length:32 toEnd:NO];
    [downloader downloadTaskFromOffset:64 length:32 toEnd:NO];

    XCTAssertEqual(gActionWorkerCancelCount, 1);
  } @finally {
    method_setImplementation(class_getInstanceMethod(actionWorkerClass,
                                                     @selector(start)),
                             originalStart);
    method_setImplementation(class_getInstanceMethod(actionWorkerClass,
                                                     @selector(cancel)),
                             originalCancel);
  }
}

@end
