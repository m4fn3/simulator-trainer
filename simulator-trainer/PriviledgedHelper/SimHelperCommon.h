//
//  SimHelperCommon.h
//  simulator-trainer
//
//  Created by Ethan Arbuckle on 5/17/25.
//

#import <Foundation/Foundation.h>
#import "SimInjectionOptions.h"
#import "EABootedSimDevice.h"
#import "EASimDevice.h"

FOUNDATION_EXPORT NSString * const kSimRuntimeHelperServiceName;
FOUNDATION_EXPORT NSString * const kSimRuntimeHelperAuthRightName;
FOUNDATION_EXPORT NSString * const kSimRuntimeHelperAuthRightDefaultRule;
FOUNDATION_EXPORT NSString * const kSimRuntimeHelperAuthRightDescription;

@protocol SimRuntimeHelperProtocol

@required
- (void)setupTweakInjectionWithOptions:(SimInjectionOptions *)options completion:(void (^)(NSError *error))completion;
- (void)mountTmpfsOverlaysAtPaths:(NSArray<NSString *> *)overlayPaths completion:(void (^)(NSError *error))completion;
- (void)unmountMountPoints:(NSArray <NSString *> *)mountPoints completion:(void (^)(NSError *))completion;

@end


@interface SimHelperCommon : NSObject

+ (void)installTweakLoaderWithOptions:(SimInjectionOptions *)options completion:(void (^)(NSError *error))completion;

+ (BOOL)mountOverlayAtPath:(NSString *)overlayPath error:(NSError **)error;
+ (BOOL)unmountOverlayAtPath:(NSString *)overlayPath error:(NSError **)error;

@end

