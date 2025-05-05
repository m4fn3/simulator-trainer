//
//  EAXCRun.m
//  simulator-trainer
//
//  Created by Ethan Arbuckle on 4/28/25.
//

#import "EAXCRun.h"
#import <objc/message.h>

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

- (NSArray<NSDictionary *> *)simDeviceInfosOnlyBooted:(BOOL)onlyBooted {
    NSArray *arguments = @[@"simctl", @"list", @"--json", @"-e", @"devices"];

    NSString *simctlOutput = [self xcrunInvokeAndWait:arguments];
    if (!simctlOutput) {
        NSLog(@"Failed to retrieve simulator devices: No output.");
        return nil;
    }

    NSError *jsonError = nil;
    NSDictionary *parsedOutput = [NSJSONSerialization JSONObjectWithData:[simctlOutput dataUsingEncoding:NSUTF8StringEncoding] options:0 error:&jsonError];
    if (!parsedOutput || jsonError) {
        NSLog(@"Failed to parse simulator device list JSON: %@ %@", jsonError.debugDescription, simctlOutput);
        return nil;
    }

    NSDictionary<NSString *, NSArray *> *deviceMap = parsedOutput[@"devices"];
    if (![deviceMap isKindOfClass:[NSDictionary class]]) {
        NSLog(@"Simulator device list JSON missing 'devices' dictionary.");
        return nil;
    }

    NSMutableArray<NSDictionary *> *result = [NSMutableArray array];
    for (NSString *runtimeKey in deviceMap) {
        
        for (NSDictionary *deviceInfo in deviceMap[runtimeKey]) {
            if (onlyBooted && ![deviceInfo[@"state"] isEqualToString:@"Booted"]) {
                continue;
            }
            
            NSArray *arguments = @[@"/Applications/Xcode.app/Contents/Developer/usr/bin/simctl", @"list", @"--json", @"-e", @"runtimes"];

            NSString *simctlOutput = [self xcrunInvokeAndWait:arguments];
            if (!simctlOutput) {
                NSLog(@"Failed to retrieve simulator devices: No output.");
                return nil;
            }
            
            NSDictionary *runtimeDetails = [self detailsForSimRuntimeWithdentifier:runtimeKey];
            NSMutableDictionary *mutableDeviceInfo = [deviceInfo mutableCopy];
            [mutableDeviceInfo addEntriesFromDictionary:@{
                @"runtime": runtimeDetails ?: @"",
            }];
            
            [result addObject:mutableDeviceInfo];
        }
    }

    return result;
}

- (BOOL)isBinaryArm64SimulatorCompatible:(NSString *)binaryPath {
    NSString *otoolOutput = [self xcrunInvokeAndWait:@[@"otool", @"-l", binaryPath]];
    NSString *lipoOutput = [self xcrunInvokeAndWait:@[@"lipo", @"-info", binaryPath]];

    return [lipoOutput containsString:@"arm64"] && [otoolOutput containsString:@"platform 7"];
}

- (BOOL)thinBinaryToArm64InPlace:(NSString *)binaryPath {
    NSArray *arguments = @[@"lipo", binaryPath, @"-thin", @"arm64", @"-o", binaryPath];
    [self xcrunInvokeAndWait:arguments];
    return YES;
}

- (BOOL)adhocSignBinary:(NSString *)binaryPath {
    NSArray *arguments = @[@"codesign", @"-f", @"-s", @"-", binaryPath];
    NSString *signOutput = [self xcrunInvokeAndWait:arguments];
    return signOutput && ![signOutput containsString:@"fail"];
}

- (BOOL)launchAppWithInjectedDylibs:(NSString *)appBundleId dylibs:(NSArray<NSString *> *)dylibPaths {
    NSArray<NSDictionary *> *bootedSimulators = [self simDeviceInfosOnlyBooted:YES];
    if (!bootedSimulators.count) {
        NSLog(@"No booted simulators available for app launch.");
        return NO;
    }

    NSString *targetSimulatorUDID = bootedSimulators[0][@"udid"];
    NSString *simulatorName = bootedSimulators[0][@"name"];
    NSLog(@"Using simulator '%@' (%@) for app launch.", simulatorName, targetSimulatorUDID);

    return [self _launchAppOnSimulator:targetSimulatorUDID appBundleId:appBundleId dylibs:dylibPaths];
}

- (BOOL)_launchAppOnSimulator:(NSString *)simulatorUDID appBundleId:(NSString *)appBundleId dylibs:(NSArray<NSString *> *)dylibPaths {
    for (NSString *dylibPath in dylibPaths) {
        if (![self isBinaryArm64SimulatorCompatible:dylibPath]) {
            [self thinBinaryToArm64InPlace:dylibPath];

            if (![self adhocSignBinary:dylibPath]) {
                NSLog(@"Failed to re-sign dylib: %@", dylibPath);
                return NO;
            }
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

@end
