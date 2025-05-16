//
//  EAXCRun.m
//  simulator-trainer
//
//  Created by Ethan Arbuckle on 4/28/25.
//

#import "EAXCRun.h"
#import <objc/message.h>
#import "AppBinaryPatcher.h"

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

    NSMutableArray *wrappedArguments = [NSMutableArray array];
    [wrappedArguments addObject:@"-m"];
    [wrappedArguments addObject:environDict[@"USER"]];
    [wrappedArguments addObject:@"-c"];
    [wrappedArguments addObject:[@"/usr/bin/xcrun " stringByAppendingString:[arguments componentsJoinedByString:@" "]]];

    id task = [[objc_getClass("NSTask") alloc] init];
    ((void (*)(id, SEL, id))objc_msgSend)(task, NSSelectorFromString(@"setLaunchPath:"), @"/usr/bin/su");
    ((void (*)(id, SEL, id))objc_msgSend)(task, NSSelectorFromString(@"setArguments:"), wrappedArguments);
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

- (NSArray<NSDictionary *> *)simDeviceRuntimes {
    NSLog(@"fetching simulator runtimes...");
    NSArray *arguments = @[@"simctl", @"list", @"--json", @"-e", @"runtimes"];

    NSString *simctlOutput = [self xcrunInvokeAndWait:arguments];
    if (!simctlOutput) {
        NSLog(@"Failed to retrieve simulator devices: No output.");
        return nil;
    }

    NSError *jsonError = nil;
    NSDictionary *parsedOutput = [NSJSONSerialization JSONObjectWithData:[simctlOutput dataUsingEncoding:NSUTF8StringEncoding] options:0 error:&jsonError];
    if (!parsedOutput || jsonError) {
        NSLog(@"Failed to parse simulator runtime list JSON: %@", jsonError.localizedDescription);
        return nil;
    }

    return [parsedOutput valueForKey:@"runtimes"];
}
    
- (NSDictionary *)detailsForSimRuntimeWithdentifier:(NSString *)simruntimeIdentifier {
    for (NSDictionary *runtimeInfo in [self simDeviceRuntimes]) {
        NSString *runtimeIdent = [runtimeInfo valueForKey:@"identifier"];
        if (runtimeIdent && [runtimeIdent isEqualToString:simruntimeIdentifier]) {
            return runtimeInfo;
        }
    }
    
    return nil;
}

- (NSDictionary *)simDeviceInfoForUDID:(NSString *)udid {
    for (id device in [self simDeviceInfosOnlyBooted:NO]) {
        NSString *udid = [((NSUUID * (*)(id, SEL))objc_msgSend)(device, NSSelectorFromString(@"UDID")) UUIDString];
        if ([udid isEqualToString:udid]) {
            return device;
        }
    }
    
    return nil;
}

- (BOOL)launchAppWithInjectedDylibs:(NSString *)appBundleId dylibs:(NSArray<NSString *> *)dylibPaths {
    NSArray<NSDictionary *> *bootedSimulators = [self simDeviceInfosOnlyBooted:YES];
    if (!bootedSimulators.count) {
        NSLog(@"No booted simulators available for app launch.");
        return NO;
    }

    NSString *targetSimulatorUDID = bootedSimulators[0][@"udid"];
    NSString *simulatorName = bootedSimulators[0][@"name"];
    return [self _launchAppOnSimulator:targetSimulatorUDID appBundleId:appBundleId dylibs:dylibPaths];
}

- (BOOL)_launchAppOnSimulator:(NSString *)simulatorUDID appBundleId:(NSString *)appBundleId dylibs:(NSArray<NSString *> *)dylibPaths {
    for (NSString *dylibPath in dylibPaths) {
        if (![AppBinaryPatcher isBinaryArm64SimulatorCompatible:dylibPath]) {
            [AppBinaryPatcher thinBinaryAtPath:dylibPath];

            [AppBinaryPatcher codesignItemAtPath:dylibPath completion:^(BOOL success, NSError *error) {
                if (!success) {
                    NSLog(@"Failed to resign dylib: %@. %@", dylibPath, error);
                }
            }];
        }
    }

    NSMutableDictionary *environment = [NSMutableDictionary dictionaryWithDictionary:[[NSProcessInfo processInfo] environment]];
    environment[@"SIMCTL_CHILD_DYLD_INSERT_LIBRARIES"] = [dylibPaths componentsJoinedByString:@":"];

    NSMutableArray *arguments = [NSMutableArray arrayWithArray:@[@"simctl", @"launch", simulatorUDID, appBundleId]];
    [arguments insertObject:@"--console" atIndex:2];

    NSString *launchOutput = [self _runXCRunCommand:arguments environment:environment waitUntilExit:YES];
    if (launchOutput) {
        NSLog(@"%@", launchOutput);
    }

    return YES;
}

- (nonnull NSArray<id> *)simDeviceInfosOnlyBooted:(BOOL)onlyBooted {
    NSError *err;
    Class SimServiceContext = objc_getClass("SimServiceContext");
    id serviceContext = ((id (*)(id, SEL, id, NSError **))objc_msgSend)(SimServiceContext, sel_registerName("sharedServiceContextForDeveloperDir:error:"), @"/Applications/Xcode.app/Contents/Developer", &err);
    id deviceSet = ((id (*)(id, SEL, NSError **))objc_msgSend)(serviceContext, sel_registerName("defaultDeviceSetWithError:"), &err);
    if (err) {
        NSLog(@"failed to get deviceset using shared service context");
        return nil;
    }
    
    return ((id (*)(id, SEL))objc_msgSend)(deviceSet, sel_registerName("devices"));
}
    

@end
    
