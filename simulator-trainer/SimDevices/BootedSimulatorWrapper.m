//
//  EABootedSimDevice.m
//  simulator-trainer
//
//  Created by Ethan Arbuckle on 4/28/25.
//

#import <objc/message.h>
#import "BootedSimulatorWrapper.h"
#import "AppBinaryPatcher.h"
#import "SimHelperCommon.h"
#import "tmpfs_overlay.h"
#import "XCRunInterface.h"

@implementation BootedSimulatorWrapper

+ (BootedSimulatorWrapper *)fromSimulatorWrapper:(SimulatorWrapper *)wrapper {
    if (!wrapper || ![wrapper isKindOfClass:[SimulatorWrapper class]]) {
        NSLog(@"fromSimulatorWrapper: requires a valid SimulatorWrapper");
        return nil;
    }
    
    if ([wrapper isKindOfClass:[BootedSimulatorWrapper class]]) {
        return (BootedSimulatorWrapper *)wrapper;
    }
    
    if (!wrapper.isBooted) {
        NSLog(@"simDevice must be booted");
        return nil;
    }
    
    return [[BootedSimulatorWrapper alloc] initWithCoreSimDevice:wrapper.coreSimDevice];
}

+ (NSArray <id> *)coreSimulatorDevices {
    Class _SimServiceContext = objc_getClass("SimServiceContext");
    SEL _sharedServiceContextForDeveloperDir = sel_registerName("sharedServiceContextForDeveloperDir:error:");
    if (_SimServiceContext == NULL) {
        NSLog(@"CoreSimulator framework issue. SimServiceContext not found");
        return nil;
    }
    
    if (![_SimServiceContext respondsToSelector:_sharedServiceContextForDeveloperDir]) {
        NSLog(@"Expected method -[SimServiceContext sharedServiceContextForDeveloperDir:error:] not found");
        return nil;
    }
    
    NSError *error = nil;
    NSString *developerDir = @"/Applications/Xcode.app/Contents/Developer";
    id simServiceContext = ((id (*)(id, SEL, id, NSError **))objc_msgSend)(_SimServiceContext, _sharedServiceContextForDeveloperDir, developerDir, &error);
    if (error || !simServiceContext) {
        NSLog(@"Failed to get SimServiceContext: %@", error);
        return nil;
    }
    
    SEL _defaultDeviceSet = sel_registerName("defaultDeviceSetWithError:");
    if (![_SimServiceContext instancesRespondToSelector:_defaultDeviceSet]) {
        NSLog(@"Expected method -[SimServiceContext defaultDeviceSetWithError:] not found");
        return nil;
    }
    
    id deviceSet = ((id (*)(id, SEL, NSError **))objc_msgSend)(simServiceContext, _defaultDeviceSet, &error);
    if (error || !deviceSet) {
        NSLog(@"Failed to get default device set: %@", error);
        return nil;
    }
    
    SEL _devices = sel_registerName("devices");
    if (![deviceSet respondsToSelector:_devices]) {
        NSLog(@"Expected method -[SimDeviceSet devices] not found");
        return nil;
    }
    
    return ((id (*)(id, SEL))objc_msgSend)(deviceSet, _devices);
}

+ (NSArray <SimulatorWrapper *> *)allDevices {
    NSMutableArray *wrappedDevices = [[NSMutableArray alloc] init];
    NSArray *coreSimDevices = [self coreSimulatorDevices];
    // For every device returned by CoreSimulator
    if (coreSimDevices) {
        for (id coreSimDevice in coreSimDevices) {
           // Grab its SimRuntime object
            id runtime = ((id (*)(id, SEL))objc_msgSend)(coreSimDevice, sel_registerName("runtime"));
            if (!runtime) {
                continue;
            }
            
            SimulatorWrapper *device = nil;
            NSString *state = ((id (*)(id, SEL))objc_msgSend)(coreSimDevice, NSSelectorFromString(@"stateString"));
            if ([state isEqualToString:@"Booted"]) {
                device = [[self alloc] initWithCoreSimDevice:coreSimDevice];
            }
            else {
                device = [[SimulatorWrapper alloc] initWithCoreSimDevice:coreSimDevice];
            }
            
            if (!device) {
                continue;
            }
            
            [wrappedDevices addObject:device];
        }
    }
    
    return wrappedDevices;
}

- (instancetype)initWithCoreSimDevice:(NSDictionary *)coreSimDevice {
    if ((self = [super initWithCoreSimDevice:coreSimDevice])) {
        self.pendingReboot = NO;
    }
    
    return self;
}

- (NSString *)invokeAndWait:(NSArray<NSString *> *)simCmdArgs {
    NSPipe *outputPipe = [NSPipe pipe];
    NSFileHandle *outputHandle = outputPipe.fileHandleForReading;

    NSDictionary *environDict = [[NSProcessInfo processInfo] environment];

    NSMutableArray *simctlSpawnArgCmd = [[NSMutableArray alloc] init];
    [simctlSpawnArgCmd addObject:[self.runtimeRoot stringByAppendingPathComponent:[simCmdArgs firstObject]]];
    if (simCmdArgs.count > 1) {
        [simctlSpawnArgCmd addObject:[[simCmdArgs subarrayWithRange:NSMakeRange(1, simCmdArgs.count - 1)] componentsJoinedByString:@" "]];
    }

    NSMutableArray *wrappedArguments = [NSMutableArray array];
    [wrappedArguments addObject:@"-m"];
    [wrappedArguments addObject:environDict[@"USER"]];
    [wrappedArguments addObject:@"-c"];
    [wrappedArguments addObject:[@"/usr/bin/xcrun simctl spawn " stringByAppendingString:[@[self.udidString, [simctlSpawnArgCmd componentsJoinedByString:@" "]] componentsJoinedByString:@" "]]];

    id task = [[objc_getClass("NSTask") alloc] init];
    ((void (*)(id, SEL, id))objc_msgSend)(task, NSSelectorFromString(@"setLaunchPath:"), @"/usr/bin/su");
    ((void (*)(id, SEL, id))objc_msgSend)(task, NSSelectorFromString(@"setArguments:"), wrappedArguments);
    ((void (*)(id, SEL, id))objc_msgSend)(task, NSSelectorFromString(@"setStandardOutput:"), outputPipe);
    ((void (*)(id, SEL, id))objc_msgSend)(task, NSSelectorFromString(@"setStandardError:"), outputPipe);

    ((void (*)(id, SEL, id))objc_msgSend)(task, NSSelectorFromString(@"setEnvironment:"), environDict);

    ((void (*)(id, SEL))objc_msgSend)(task, NSSelectorFromString(@"launch"));

    ((void (*)(id, SEL))objc_msgSend)(task, NSSelectorFromString(@"waitUntilExit"));
    NSData *outputData = [outputHandle readDataToEndOfFile];
    return [[NSString alloc] initWithData:outputData encoding:NSUTF8StringEncoding];
}

- (NSArray <NSString *> *)directoriesToOverlay {
    return @[
        [self.runtimeRoot stringByAppendingPathComponent:@"/usr/lib"],
        [self.runtimeRoot stringByAppendingPathComponent:@"/Library"],
        [self.runtimeRoot stringByAppendingPathComponent:@"/private/var"],
    ];
}

- (NSDictionary *)bootstrapFilesToCopy {
    NSDictionary *bundleFiles = @{
        @"FLEX.dylib": @"/Library/MobileSubstrate/DynamicLibraries/FLEX.dylib",
        @"FLEX.plist": @"/Library/MobileSubstrate/DynamicLibraries/FLEX.plist",
        @"CydiaSubstrate": @"/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate",
        @"libhooker.dylib": @"/usr/lib/libhooker.dylib",
        @"loader.dylib": @"/usr/lib/loader.dylib",
    };
    
    NSMutableDictionary *filesToCopy = [[NSMutableDictionary alloc] init];
    NSString *simRuntimePath = self.runtimeRoot;
    for (NSString *bundleFile in bundleFiles) {
        NSString *fullSourcePath = [[NSBundle mainBundle] pathForResource:bundleFile ofType:nil];
        if (!fullSourcePath) {
            continue;
        }
        
        filesToCopy[fullSourcePath] = [simRuntimePath stringByAppendingPathComponent:bundleFiles[bundleFile]];
    }
    
    return [filesToCopy copy];
}

- (BOOL)hasOverlays {    
    NSString *libraryMountPath = [self.runtimeRoot stringByAppendingPathComponent:@"/usr/lib/"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:libraryMountPath]) {
        NSLog(@"simruntime does not have a `/usr/lib/` directory: %@", self.runtimeRoot);
        return NO;
    }
    
    if (!is_mount_point(libraryMountPath.UTF8String)) {
        return NO;
    }
    
    if (!is_tmpfs_mount(libraryMountPath.UTF8String)) {
        NSLog(@"Mount point is not a tmpfs overlay: %@", libraryMountPath);
        return NO;
    }
    
    return YES;
}

- (BOOL)hasInjection {
    if (!self.runtimeRoot) {
        NSLog(@"No runtime root?");
        return NO;
    }

    NSString *libPath = [self.runtimeRoot stringByAppendingPathComponent:@"/usr/lib/libobjc.A.dylib"];
    NSString *otoolOutput = [[XCRunInterface sharedInstance] xcrunInvokeAndWait:@[@"otool", @"-l", libPath]];
    if (!otoolOutput) {
        NSLog(@"Failed to get otool output");
        return NO;
    }
    
    return [otoolOutput containsString:[self tweakLoaderDylibPath]];
}

- (NSString *)tweakLoaderDylibPath {
    // RUNTIME_ROOT/usr/lib/loader.dylib
    NSString *loaderPath = @"/usr/lib/loader.dylib";
    return [self.runtimeRoot stringByAppendingPathComponent:loaderPath];
}

- (void)shutdownWithCompletion:(void (^)(NSError *error))completion {
    if (!self.isBooted) {
        [self reloadDeviceState];
        if (!self.isBooted) {
            NSLog(@"Cannot shutdown a device that is not booted: %@", self);
            return;
        }
    }
    
    // Shutdown the simulator. This doesn't reliably terminate the actual Simulator frontend app process
    ((void (*)(id, SEL, id))objc_msgSend)(self.coreSimDevice, NSSelectorFromString(@"shutdownAsyncWithCompletionHandler:"), ^(NSError *error) {
        if (error) {
            NSLog(@"Failed to shutdown device: %@", error);
            return;
        }
        
        for (int i = 0; i < 10 && self.isBooted; i++) {
            NSLog(@"Waiting for device to shutdown: %@", self);
            [self reloadDeviceState];
            [NSThread sleepForTimeInterval:1.0];
        }
        
        // If the device was shutdown for a reboot, boot it again now.
        // Note: Reboots will not call the didShutdown: delegate method
        if (self.pendingReboot) {
            // -boot will cleanup the pendingReboot
            [self bootWithCompletion:nil];
            return;
        }
        
        if (self.delegate) {
            if (self.isBooted && [self.delegate respondsToSelector:@selector(device:didFailToShutdownWithError:)]) {
                // Device is still booted, something went wrong
                [self.delegate device:self didFailToShutdownWithError:[NSError errorWithDomain:NSOSStatusErrorDomain code:paramErr userInfo:@{NSLocalizedDescriptionKey: @"Failed to shutdown device"}]];
            }
            else if (!self.isBooted && [self.delegate respondsToSelector:@selector(deviceDidShutdown:)]) {
                [self.delegate deviceDidShutdown:self];
            }
        }
        
        if (completion) {
            completion(error);
        }
    });
}

- (void)reboot {
    if (!self.isBooted) {
        NSLog(@"Cannot reboot a device that is not booted: %@", self);
        return;
    }
    
    if (self.pendingReboot) {
        NSLog(@"Already pending reboot: %@", self);
        return;
    }
    
    self.pendingReboot = YES;
    [self shutdownWithCompletion:nil];
}

- (void)respring {
    [[XCRunInterface sharedInstance] xcrunInvokeAndWait:@[@"killall", @"-9", @"backboardd"]];
}

- (BOOL)isJailbroken {
    return [self hasOverlays] || [self hasInjection];
}

@end
