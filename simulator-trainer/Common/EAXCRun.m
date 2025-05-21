//
//  EAXCRun.m
//  simulator-trainer
//
//  Created by Ethan Arbuckle on 4/28/25.
//

#import "EAXCRun.h"
#import <objc/message.h>
#import "EABootedSimDevice.h"
#import "AppBinaryPatcher.h"

@interface EAXCRun ()
- (NSString * _Nullable)_runXCRunCommand:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> * _Nullable)environment waitUntilExit:(BOOL)waitUntilExit;
@end

@implementation EAXCRun

+ (instancetype)sharedInstance {
    static EAXCRun *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (NSString *)xcrunInvokeAndWait:(NSArray<NSString *> *)arguments {
    return [self _runXCRunCommand:arguments environment:nil waitUntilExit:YES];
}
    
- (NSString *)_runXCRunCommand:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)customEnvironment waitUntilExit:(BOOL)waitUntilExit {
    NSPipe *outputPipe = [NSPipe pipe];
    NSFileHandle *outputHandle = outputPipe.fileHandleForReading;

    NSDictionary *environDict = [[NSProcessInfo processInfo] environment];

    id task = [[objc_getClass("NSTask") alloc] init];
    ((void (*)(id, SEL, id))objc_msgSend)(task, NSSelectorFromString(@"setLaunchPath:"), @"/usr/bin/xcrun");
    ((void (*)(id, SEL, id))objc_msgSend)(task, NSSelectorFromString(@"setArguments:"), arguments);
    ((void (*)(id, SEL, id))objc_msgSend)(task, NSSelectorFromString(@"setStandardOutput:"), outputPipe);
    ((void (*)(id, SEL, id))objc_msgSend)(task, NSSelectorFromString(@"setStandardError:"), outputPipe);
 
    if (customEnvironment) {
        NSMutableDictionary *mutableEnvironDict = [NSMutableDictionary dictionaryWithDictionary:environDict];
        [mutableEnvironDict addEntriesFromDictionary:customEnvironment];
        environDict = mutableEnvironDict;
    }
    ((void (*)(id, SEL, id))objc_msgSend)(task, NSSelectorFromString(@"setEnvironment:"), environDict);

    ((void (*)(id, SEL))objc_msgSend)(task, NSSelectorFromString(@"launch"));

    if (waitUntilExit) {
        ((void (*)(id, SEL))objc_msgSend)(task, NSSelectorFromString(@"waitUntilExit"));
        NSData *outputData = [outputHandle readDataToEndOfFile];
        return [[NSString alloc] initWithData:outputData encoding:NSUTF8StringEncoding];
    }

    return nil;
}

- (NSDictionary *)coreSimulatorDeviceForUdid:(NSString *)targetUdid{
    NSArray *coreSimDevices = [EABootedSimDevice coreSimulatorDevices];
    for (int i = 0; i < coreSimDevices.count; i++) {
        NSDictionary *coreSimDevice = coreSimDevices[i];
        NSString *deviceUdid = [((NSUUID * (*)(id, SEL))objc_msgSend)(coreSimDevice, NSSelectorFromString(@"UDID")) UUIDString];
        if ([deviceUdid isEqualToString:targetUdid]) {
            return coreSimDevice;
        }
    }
    
    return nil;
}
//
//- (BOOL)launchAppWithInjectedDylibs:(NSString *)appBundleId dylibs:(NSArray<NSString *> *)dylibPaths {
//    NSArray<NSDictionary *> *bootedSimulators = [self simDeviceInfosOnlyBooted:YES];
//    if (!bootedSimulators.count) {
//        NSLog(@"No booted simulators available for app launch.");
//        return NO;
//    }
//
//    NSString *targetSimulatorUDID = bootedSimulators[0][@"udid"];
//    return [self _launchAppOnSimulator:targetSimulatorUDID appBundleId:appBundleId dylibs:dylibPaths];
//}
//
//- (BOOL)_launchAppOnSimulator:(NSString *)simulatorUDID appBundleId:(NSString *)appBundleId dylibs:(NSArray<NSString *> *)dylibPaths {
//    for (NSString *dylibPath in dylibPaths) {
//        if (![AppBinaryPatcher isBinaryArm64SimulatorCompatible:dylibPath]) {
//            [AppBinaryPatcher thinBinaryAtPath:dylibPath];
//
//            [AppBinaryPatcher codesignItemAtPath:dylibPath completion:^(BOOL success, NSError *error) {
//                if (!success) {
//                    NSLog(@"Failed to resign dylib: %@. %@", dylibPath, error);
//                }
//            }];
//        }
//    }
//
//    NSMutableDictionary *environment = [NSMutableDictionary dictionaryWithDictionary:[[NSProcessInfo processInfo] environment]];
//    environment[@"SIMCTL_CHILD_DYLD_INSERT_LIBRARIES"] = [dylibPaths componentsJoinedByString:@":"];
//
//    NSMutableArray *arguments = [NSMutableArray arrayWithArray:@[@"simctl", @"launch", simulatorUDID, appBundleId]];
//    [arguments insertObject:@"--console" atIndex:2];
//
//    NSString *launchOutput = [self _runXCRunCommand:arguments environment:environment waitUntilExit:YES];
//    if (launchOutput) {
//        NSLog(@"%@", launchOutput);
//    }
//
//    return YES;
//}

@end
    
