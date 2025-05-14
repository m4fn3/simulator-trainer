//
//  EABootedSimDevice.m
//  simulator-trainer
//
//  Created by Ethan Arbuckle on 4/28/25.
//

#import "EABootedSimDevice.h"
#import "EAXCRun.h"
#import "tmpfs_overlay.h"
#import <objc/message.h>
#import "AppBinaryPatcher.h"
#import "CommandRunner.h"

@implementation EABootedSimDevice

+ (EABootedSimDevice *)fromSimDevice:(EASimDevice *)simDevice {
    if (!simDevice || ![simDevice isKindOfClass:[EASimDevice class]]) {
        NSLog(@"simDevice must be a valid EASimDevice");
        return nil;
    }
    
    if ([simDevice isKindOfClass:[EABootedSimDevice class]]) {
        return (EABootedSimDevice *)simDevice;
    }
    
    if (!simDevice.isBooted) {
        NSLog(@"simDevice must be booted");
        return nil;
    }
    
    return [[EABootedSimDevice alloc] initWithDict:simDevice.simInfoDict];
}
//
//+ (EABootedSimDevice *)bootedDevice {
//    NSArray <EABootedSimDevice *> *runningSimulators = [EABootedSimDevice allBootedDevices];
//    if (runningSimulators.count > 1) {
//        NSLog(@"Multiple simulators are booted, choosing the first one. Running Sims: %@", runningSimulators);
//    }
//    
//   return [runningSimulators firstObject];
//}

+ (NSArray <EABootedSimDevice *> *)allBootedDevices {
    NSArray *runningSimulatorInfos = [[EAXCRun sharedInstance] simDeviceInfosOnlyBooted:YES];
    if (!runningSimulatorInfos || runningSimulatorInfos.count == 0) {
        NSLog(@"Cannot return a running simulator because no simulators are found to be running");
        return nil;
    }
    
    NSMutableArray *devices = [[NSMutableArray alloc] init];
    for (NSDictionary *deviceInfo in runningSimulatorInfos) {
        EABootedSimDevice *simdev = [[EABootedSimDevice alloc] initWithDict:deviceInfo];
        if (simdev) {
            [devices addObject:simdev];
        }
    }
    
    return devices;
}

+ (NSArray <EASimDevice *> *)allDevices {
    NSArray *simulatorInfos = [[EAXCRun sharedInstance] simDeviceInfosOnlyBooted:NO];
    if (!simulatorInfos || simulatorInfos.count == 0) {
        return nil;
    }
    
    NSMutableArray *devices = [[NSMutableArray alloc] init];
    for (NSDictionary *deviceInfo in simulatorInfos) {
        EASimDevice *simdev = [[EASimDevice alloc] initWithDict:deviceInfo];
        if (!simdev || !simdev.platform) {
            continue;
        }
        
        if (simdev.isBooted) {
            EABootedSimDevice *bootedDevice = [EABootedSimDevice fromSimDevice:simdev];
            if (bootedDevice) {
                simdev = bootedDevice;
            }
        }
        
        if (simdev) {
            [devices addObject:simdev];
        }
    }
    
    return devices;
}

- (instancetype)initWithDict:(NSDictionary *)simInfoDict {
    if ((self = [super initWithDict:simInfoDict])) {
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

- (void)unmountNow {
    for (NSString *overlayPath in [self directoriesToOverlay]) {
        if (unmount_if_mounted(overlayPath.UTF8String) != 0) {
            NSLog(@"Failed to unmount path: %@", overlayPath);
        }
    }
}

- (BOOL)prepareJbFilesystem {
    for (NSString *overlayPath in [self directoriesToOverlay]) {
        if (![[NSFileManager defaultManager] fileExistsAtPath:overlayPath]) {
            NSLog(@"host-relative mount point path does not exist: %@", overlayPath);
            [self unmountNow];
            return NO;
        }
        
        if (create_or_remount_overlay_symlinks(overlayPath.UTF8String) != 0) {
            NSLog(@"Failed to mount host-relative path: %@", overlayPath);
            [self unmountNow];
            return NO;
        }
        
        NSString *runtimeRelPath = [overlayPath stringByReplacingOccurrencesOfString:self.runtimeRoot withString:@""];
        NSLog(@"Setup overlay at sim://%@", runtimeRelPath);
    }
    
    // mkdir:
    // /private/var/tmp/
    // /Library/MobileSubstrate/DynamicLibraries/
    NSString *tmpDir = [self.runtimeRoot stringByAppendingPathComponent:@"/private/var/tmp"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:tmpDir]) {
        NSError *error = nil;
        [[NSFileManager defaultManager] createDirectoryAtPath:tmpDir withIntermediateDirectories:YES attributes:nil error:&error];
        if (error) {
            NSLog(@"Failed to create tmp directory: %@", error);
            return NO;
        }
    }
    
    NSString *libDir = [self.runtimeRoot stringByAppendingPathComponent:@"/Library/MobileSubstrate/DynamicLibraries"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:libDir]) {
        NSError *error = nil;
        [[NSFileManager defaultManager] createDirectoryAtPath:libDir withIntermediateDirectories:YES attributes:nil error:&error];
        if (error) {
            NSLog(@"Failed to create lib directory: %@", error);
            return NO;
        }
    }
    
    NSDictionary *bundleFiles = @{
        @"FLEX.dylib": @"/Library/MobileSubstrate/DynamicLibraries/FLEX.dylib",
        @"FLEX.plist": @"/Library/MobileSubstrate/DynamicLibraries/FLEX.plist",
        @"CydiaSubstrate": @"/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate",
        @"libhooker.dylib": @"/usr/lib/libhooker.dylib",
        @"loader.dylib": @"/usr/lib/loader.dylib",
    };
    
    for (NSString *bundleFile in bundleFiles) {
        NSString *sourcePath = [[NSBundle mainBundle] pathForResource:bundleFile ofType:nil];
        if (!sourcePath) {
            NSLog(@"Failed to find bundle file: %@", bundleFile);
            continue;
        }
        
        NSString *targetPath = [self.runtimeRoot stringByAppendingPathComponent:bundleFiles[bundleFile]];
        if ([[NSFileManager defaultManager] fileExistsAtPath:targetPath]) {
            NSLog(@"File already exists at target path: %@", targetPath);
            continue;
        }
        
        NSString *targetDir = [targetPath stringByDeletingLastPathComponent];
        if (![[NSFileManager defaultManager] fileExistsAtPath:targetDir]) {
            NSError *error = nil;
            [[NSFileManager defaultManager] createDirectoryAtPath:targetDir withIntermediateDirectories:YES attributes:nil error:&error];
            if (error) {
                NSLog(@"Failed to create target directory: %@", error);
                continue;
            }
        }
        
        NSError *error = nil;
        [[NSFileManager defaultManager] copyItemAtPath:sourcePath toPath:targetPath error:&error];
        if (error) {
            NSLog(@"Failed to copy bundle file: %@, error: %@", bundleFile, error);
            continue;
        }        
    }
    
    return YES;
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
    NSString *stdoutString = nil;
    NSError *error = nil;
    [CommandRunner runCommand:@"/usr/bin/otool" withArguments:@[@"-l", libPath] stdoutString:&stdoutString error:&error];
    
    if (!stdoutString || error) {
        NSLog(@"Failed to get otool output: %@", error);
        return NO;
    }
    
    return [stdoutString containsString:[self pathToLoaderDylib]];
}

- (void)setupInjection {
    NSString *simRelativeLoaderPath = [self pathToLoaderDylib];
    if (![[NSFileManager defaultManager] fileExistsAtPath:simRelativeLoaderPath]) {
        
        NSString *loaderPath = [[NSBundle mainBundle] pathForResource:@"loader" ofType:@"dylib"];
        NSLog(@"Using loader from %@", loaderPath);
        
        NSError *error = nil;
        [[NSFileManager defaultManager] copyItemAtPath:loaderPath toPath:simRelativeLoaderPath error:&error];
        if (error) {
            NSLog(@"Failed to copy loader into overlay: %@", error);
            return;
        }
        
        NSLog(@"Copied %@ to %@", loaderPath, simRelativeLoaderPath);
    }
    
    NSString *libPath = [self.runtimeRoot stringByAppendingPathComponent:@"/usr/lib/libobjc.A.dylib"];
    [AppBinaryPatcher injectDylib:simRelativeLoaderPath intoBinary:libPath completion:^(BOOL success, NSError *error) {
        if (!success) {
            NSLog(@"Failed: %@", error.localizedDescription);
        }
        else {
            NSLog(@"Succesfully patched %@", libPath);
            [CommandRunner runCommand:@"/usr/bin/killall" withArguments:@[@"-9", @"backboardd"] stdoutString:nil error:nil];
        }
    }];
}

- (NSString *)pathToLoaderDylib {
    NSString *runtimeLibraryDir = [self.runtimeRoot stringByAppendingPathComponent:@"/usr/lib"];
    return [runtimeLibraryDir stringByAppendingPathComponent:@"loader.dylib"];
}

- (void)unjailbreak {
    if (!self.isBooted || ![self isJailbroken]) {
        NSLog(@"Cannot unjailbreak a device that is not booted or not jailbroken: %@", self);
        return;
    }
    
    [self _performBlockOnCommandQueue:^{
        // Treat this as a reboot
        self.pendingReboot = YES;
        [self shutdown];
        
        if ([self hasOverlays]) {
            [self unmountNow];
        }
        
        BOOL isReset = NO;
        for (int i = 0; i < 10; i++) {
            [self reloadDeviceState];
            isReset = !self.isBooted && ![self isJailbroken];
            if (isReset) {
                break;
            }
            
            [NSThread sleepForTimeInterval:1.0];
        }
        
        if (!isReset) {
            NSLog(@"Failed to unjailbreak simulator: %@", self);
            // Cancel reboot
            self.pendingReboot = NO;
            return;
        }
        
        [self boot];
    }];
}

- (void)shutdown {
    if (!self.isBooted) {
        NSLog(@"Cannot shutdown a device that is not booted: %@", self);
        return;
    }
    
    [self _performBlockOnCommandQueue:^{
        [[EAXCRun sharedInstance] xcrunInvokeAndWait:@[@"simctl", @"shutdown", self.udidString]];
        
        for (int i = 0; i < 10 && !self.isBooted; i++) {
            [self reloadDeviceState];
            if (!self.isBooted) {
                break;
            }
            
            [NSThread sleepForTimeInterval:1.0];
        }
                
        // If the device was shutdown for a reboot, boot it again now.
        // Note: Reboots will not call the didShutdown: delegate method
        if (self.pendingReboot) {
            // -boot will reset pendingReboot upon completion,
            // then call delegate method deviceDidReboot:
            [self boot];
            return;
        }
        
        if (self.delegate) {
            if (!self.isBooted && [self.delegate respondsToSelector:@selector(deviceDidShutdown:)]) {
                [self.delegate deviceDidShutdown:self];
            }
        }
    }];
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
    [self shutdown];
}

- (BOOL)isJailbroken {
    return [self hasOverlays] || [self hasInjection];
}

@end
