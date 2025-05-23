//
//  HelperConnection.h
//  simulator-trainer
//
//  Created by m1book on 5/22/25.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface HelperConnection : NSObject

- (NSXPCConnection *)getConnection;

// These mirror the helper protocol methods
- (void)mountTmpfsOverlaysAtPaths:(NSArray<NSString *> *)overlayPaths completion:(void (^)(NSError * _Nullable error))completion;
- (void)setupTweakInjectionWithOptions:(SimInjectionOptions *)options completion:(void (^)(NSError * _Nullable error))completion;
- (void)unmountMountPoints:(NSArray<NSString *> *)mountPoints completion:(void (^)(NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
