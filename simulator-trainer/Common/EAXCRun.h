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

- (NSString * _Nullable)xcrunInvokeAndWait:(NSArray<NSString *> *)arguments;
- (NSArray <id>  * _Nullable)simDeviceRuntimes;
- (NSDictionary * _Nullable )detailsForSimRuntimeWithdentifier:(NSString *)simruntimeIdentifier;
- (NSDictionary * _Nullable)simDeviceInfoForUDID:(NSString *)udid;

- (NSArray <NSDictionary *> * _Nullable)simDeviceInfosOnlyBooted:(BOOL)onlyBooted;
- (BOOL)launchAppWithInjectedDylibs:(NSString *)appBundleId dylibs:(NSArray<NSString *> *)dylibPaths;
- (BOOL)_launchAppOnSimulator:(NSString *)simulatorUDID appBundleId:(NSString *)appBundleId dylibs:(NSArray<NSString *> *)dylibPaths;

- (NSString *)_runCommandAsUnprivilegedUser:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> * _Nullable)customEnvironment waitUntilExit:(BOOL)waitUntilExit;
- (NSString *)_runXCRunCommand:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> * _Nullable)customEnvironment waitUntilExit:(BOOL)waitUntilExit;

@end

NS_ASSUME_NONNULL_END
