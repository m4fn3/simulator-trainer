//
//  EAXCRun.h
//  simulator-trainer
//
//  Created by Ethan Arbuckle on 4/28/25.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface EAXCRun : NSObject

+ (instancetype)sharedInstance;

- (NSString *)xcrunInvokeAndWait:(NSArray<NSString *> *)arguments;
- (NSString *)_runXCRunCommand:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> * _Nullable)environment waitUntilExit:(BOOL)waitUntilExit;
- (NSArray<NSDictionary *> *)simDeviceRuntimes;
- (NSDictionary *)detailsForSimRuntimeWithdentifier:(NSString *)simruntimeIdentifier;
- (NSDictionary *)simDeviceInfoForUDID:(NSString *)udid;

- (NSArray <NSDictionary *> *)simDeviceInfosOnlyBooted:(BOOL)onlyBooted;
- (BOOL)launchAppWithInjectedDylibs:(NSString *)appBundleId dylibs:(NSArray<NSString *> *)dylibPaths;
- (BOOL)_launchAppOnSimulator:(NSString *)simulatorUDID appBundleId:(NSString *)appBundleId dylibs:(NSArray<NSString *> *)dylibPaths;

@end

NS_ASSUME_NONNULL_END
