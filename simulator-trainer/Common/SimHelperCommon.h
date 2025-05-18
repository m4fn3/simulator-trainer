//
//  SimHelperCommon.h
//  simulator-trainer
//
//  Created by Ethan Arbuckle on 5/17/25.
//

#import <Foundation/Foundation.h>

FOUNDATION_EXPORT NSString * const kSimRuntimeHelperServiceName;
FOUNDATION_EXPORT NSString * const kSimRuntimeHelperAuthRightName;
FOUNDATION_EXPORT NSString * const kSimRuntimeHelperAuthRightDefaultRule;
FOUNDATION_EXPORT NSString * const kSimRuntimeHelperAuthRightDescription;


@protocol SimRuntimeHelperProtocol
@required
// Overlay mounting
- (void)mountOverlayOnSimRuntime:(NSString *)simRuntimePath overlayPath:(NSString *)overlayPath completion:(void (^)(NSError *error, NSString *simRuntimePath))completion;
- (void)unmountOverlayOnSimRuntime:(NSString *)simRuntimePath completion:(void (^)(NSError *error, NSString *simRuntimePath))completion;
// Jailbreaking
- (void)jailbreakSimRuntime:(NSString *)simRuntimePath completion:(void (^)(NSError *error, NSString *simRuntimePath))completion;
- (void)unjailbreakSimRuntime:(NSString *)simRuntimePath completion:(void (^)(NSError *error, NSString *simRuntimePath))completion;
@end


@interface SimHelperCommon : NSObject

+ (void)grantAuthorizationRights:(AuthorizationRef)authRef;

@end

