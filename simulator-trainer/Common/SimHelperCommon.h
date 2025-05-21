//
//  SimHelperCommon.h
//  simulator-trainer
//
//  Created by Ethan Arbuckle on 5/17/25.
//

#import <Foundation/Foundation.h>
#import "EASimDevice.h"
#import "EABootedSimDevice.h"
#import "SimInjectionOptions.h"

FOUNDATION_EXPORT NSString * const kSimRuntimeHelperServiceName;
FOUNDATION_EXPORT NSString * const kSimRuntimeHelperAuthRightName;
FOUNDATION_EXPORT NSString * const kSimRuntimeHelperAuthRightDefaultRule;
FOUNDATION_EXPORT NSString * const kSimRuntimeHelperAuthRightDescription;


@protocol SimRuntimeHelperProtocol
@required

- (void)unmountOverlayOnSimRuntime:(NSString *)overlayMountPoint completion:(void (^)(NSError *error, NSString *simRuntimePath))completion;

- (void)setupTweakInjectionWithOptions:(SimInjectionOptions *)options completion:(void (^)(NSError *error))completion;
- (void)mountTmpfsOverlaysAtPaths:(NSArray<NSString *> *)overlayPaths completion:(void (^)(NSError *error))completion;

- (void)unjailbreakSimWithUdid:(NSString *)simUdid completion:(void (^)(NSError *error, NSString *simRuntimePath))completion;
@end


@interface SimHelperCommon : NSObject

+ (void)grantAuthorizationRights:(AuthorizationRef)authRef;

+ (void)installTweakLoaderWithOptions:(SimInjectionOptions *)options completion:(void (^)(NSError *error))completion;

+ (void)unmountOverlayAtPath:(NSString *)overlayPath completion:(void (^)(NSError *))completion;
+ (BOOL)mountOverlayAtPath:(NSString *)overlayPath error:(NSError **)error;

@end

