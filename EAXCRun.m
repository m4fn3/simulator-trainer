//
//  EAXCRun.m
//  simulator-trainer
//
//  Created by Ethan Arbuckle on 4/28/25.
//

#import "EAXCRun.h"
#import <objc/message.h>

@implementation EAXCRun

static NSString *xcrun(NSArray *xcrunCommand, NSDictionary *environment, BOOL waitUntilExit) {
    NSPipe *pipe = [NSPipe pipe];
    NSFileHandle *file = pipe.fileHandleForReading;
    
    NSArray *fullCommand = [@[@"/usr/bin/xcrun"] arrayByAddingObjectsFromArray:xcrunCommand];
    
    id task = [[objc_getClass("NSTask") alloc] init];
    ((void (*)(id, SEL, id))objc_msgSend)(task, NSSelectorFromString(@"setLaunchPath:"), @"/usr/bin/env");
    ((void (*)(id, SEL, id))objc_msgSend)(task, NSSelectorFromString(@"setArguments:"), fullCommand);
    ((void (*)(id, SEL, id))objc_msgSend)(task, NSSelectorFromString(@"setStandardOutput:"), pipe);
    ((void (*)(id, SEL, id))objc_msgSend)(task, NSSelectorFromString(@"setStandardError:"), pipe);
    if (environment) {
        ((void (*)(id, SEL, id))objc_msgSend)(task, NSSelectorFromString(@"setEnvironment:"), environment);
    }
    
    // Run the task
    ((void (*)(id, SEL))objc_msgSend)(task, NSSelectorFromString(@"launch"));
    
    if (waitUntilExit) {
        ((void (*)(id, SEL))objc_msgSend)(task, NSSelectorFromString(@"waitUntilExit"));
        NSData *data = [file readDataToEndOfFile];
        return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    }
    
    return nil;
}

NSArray *getSimulatorDevices(BOOL onlyBooted) {
    // Get details on all available Simulators
    NSArray *command = @[@"simctl", @"list", @"--json", @"-e", @"devices"];

    NSString *stdoutString = xcrun(command, nil, YES);
    NSError *error = nil;
    NSDictionary *simDevicesDict = [NSJSONSerialization JSONObjectWithData:[stdoutString dataUsingEncoding:NSUTF8StringEncoding] options:0 error:&error];
    if (!simDevicesDict || error) {
        NSLog(@"Cannot list simulator devices. Failed to read output from simctl");
        if (error) {
            NSLog(@"Error: %@", error);
            NSLog(@"simctl output: %@", stdoutString);
        }
        
        return nil;
    }
    
    NSDictionary <NSString *, NSArray *> *simruntimeMap = [simDevicesDict valueForKey:@"devices"];
    if (!simruntimeMap || ![simruntimeMap isKindOfClass:[NSDictionary class]]) {
        NSLog(@"No valid devices found in simctl output");
        NSLog(@"simctl output: %@", stdoutString);
        return nil;
    }

    // If onlyBooted is true, filter out devices that are not currently off
    NSMutableArray *filteredDevices = [[NSMutableArray alloc] init];
    for (NSString *simruntimeKey in simruntimeMap) {
        
        for (NSDictionary *simDevice in simruntimeMap[simruntimeKey]) {
            
            if (onlyBooted && ![simDevice[@"state"] isEqualToString:@"Booted"]) {
                continue;
            }
            
            [filteredDevices addObject:simDevice];
        }
    }
    
    return filteredDevices;
}

- (BOOL)isBinaryCompatibleWithSimulator:(NSString *)binaryPath {
    // Check the binary's LC_BUILD_VERSION command to see if it contains the simulator platform (7)
    NSString *otoolOutput = xcrun(@[@"otool", @"-l", binaryPath], nil, YES);
    NSString *lipoOutput = xcrun(@[@"lipo", @"-info", binaryPath], nil, YES);
    return [lipoOutput containsString:@"arm64"] && [otoolOutput containsString:@"platform 7"];
}

- (BOOL)convertFatMachoToThin:(NSString *)fatMachoPath) {
    // Thin the binary to arm64 only
    NSArray *command = @[@"lipo", fatMachoPath, @"-thin", @"arm64", @"-o", fatMachoPath];
    xcrun(command, nil, YES);
    return YES;
}

- (BOOL)adhocCodesignDylib:(NSString *)dylibPath {
    // Sign the dylib with an ad-hoc signature
    NSArray *command = @[@"codesign", @"-f", @"-s", @"-", dylibPath];
    NSString *stdoutString = xcrun(command, nil, YES);
    return ![stdoutString containsString:@"fail"];
}

BOOL launchAppOnSimulatorWithDylibs(NSString *simulatorUUID, NSString *appBundleId, NSArray *dylibPaths) {
    // Make sure the dylibs have simulator support
    for (NSString *dylibPath in dylibPaths) {
        if (!isArm64SimulatorPlatform(dylibPath)) {
            // convertPlatformToSimulatom needs non-fat binaries
            thinSlimArm64Inplace(dylibPath);
//            convertPlatformToSimulator_single(dylibPath.UTF8String);
            
            // Resign the modified dylib
            if (!adhocSignDylibInplace(dylibPath)) {
                NSLog(@"Failed to sign dylib: %@", dylibPath);
                return NO;
            }
        }
    }
    
    // simctl will forward env vars that begin with SIMCTL_CHILD_ to the spawned Simulator process.
    // DYLD_INSERT_LIBRARIES=tweak1.dylib:tweak2.dylib => SIMCTL_CHILD_DYLD_INSERT_LIBRARIES=...
    NSMutableDictionary *env = [NSMutableDictionary dictionaryWithDictionary:[[NSProcessInfo processInfo] environment]];
    env[@"SIMCTL_CHILD_DYLD_INSERT_LIBRARIES"] = [dylibPaths componentsJoinedByString:@":"];
    
    // When true, this will block until the Simulator process exits. When it exits, all output printed
    // by the process while it was running will get dumped to stdout. (It could be streamed with more effort)
    BOOL withConsole = YES;

    NSArray *command = @[@"simctl", @"launch", simulatorUUID, appBundleId];
    if (withConsole) {
        NSMutableArray *commandCopy = [command mutableCopy];
        [commandCopy insertObject:@"--console"  atIndex:2];
        command = commandCopy;
    }

    NSString *output = xcrun(command, env, withConsole);
    if (withConsole && output) {
        NSLog(@"%@", output);
    }
    return YES;
}

- (BOOL)launchApp:(NSString *)appBundleId withDylibs:(NSArray *)dylibPaths {
    
    NSArray *bootedSims = getSimulatorDevices(YES);
    if (!bootedSims || bootedSims.count == 0) {
        NSLog(@"No booted simulators found");
        return NO;
    }
    
    NSString *firstBootedSimUdid = bootedSims[0][@"udid"];
    NSString *simulatorName = bootedSims[0][@"name"];
    NSLog(@"Launching on simulator: %@ (%@)", simulatorName, firstBootedSimUdid);
    return launchAppOnSimulatorWithDylibs(firstBootedSimUdid, appBundleId, dylibPaths);
}

@end
