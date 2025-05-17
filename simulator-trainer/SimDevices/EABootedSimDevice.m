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
    
    return [[EABootedSimDevice alloc] initWithCoreSimDevice:simDevice.coreSimDevice];
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

+ (NSArray <EASimDevice *> *)allDevices {
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
            
            // And use the SimRuntime to build a helper wrapper object
            EASimDevice *simdev = [[EASimDevice alloc] initWithCoreSimDevice:coreSimDevice];
            if (simdev) {
                [wrappedDevices addObject:simdev];
            }
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

- (BOOL)setupInjection {
    NSString *simRelativeLoaderPath = [self pathToLoaderDylib];
    if (![[NSFileManager defaultManager] fileExistsAtPath:simRelativeLoaderPath]) {        
        NSString *loaderPath = [[NSBundle mainBundle] pathForResource:@"loader" ofType:@"dylib"];
        
        NSError *error = nil;
        [[NSFileManager defaultManager] copyItemAtPath:loaderPath toPath:simRelativeLoaderPath error:&error];
        if (error) {
            NSLog(@"Failed to copy loader into overlay: %@", error);
            return NO;
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
    
    return YES;
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
    
    // Unjailbreaking is done by unmounting the tmpfs overlays and rebooting the simulator
    [self _performBlockOnCommandQueue:^{
        // The sim has to be fully-shutdown before unmounting, otherwise macOS will kernel panic
        [self shutdownWithCompletion:^(NSError * _Nonnull error) {
            if (error) {
                NSLog(@"Failed to shutdown device for unjailbreak %@ with error: %@", self, error);
                return;
            }
            
            // Unmount the overlays now that the device is shutdown
            if ([self hasOverlays]) {
                [self unmountNow];
            }
            
            // Confirm the device is not booted, and that jailbreak overlays are not mounted
            BOOL removedJailbreak = NO;
            for (int i = 0; i < 10; i++) {
                [self reloadDeviceState];
                
                removedJailbreak = self.isBooted == NO && [self hasOverlays] == NO && [self hasInjection] == NO;
                if (removedJailbreak) {
                    // The device booted and is no longer jailbroken
                    break;
                }
                
                [NSThread sleepForTimeInterval:1.0];
            }
            
            // Don't continue with the reboot if the jailbreak failed to be removed
            if (!removedJailbreak) {
                NSLog(@"Failed to unjailbreak simulator: %@", self);
                return;
            }
            
            // Success. Sim will boot into its original state
            [self bootWithCompletion:nil];
        }];
    }];
}

- (void)jailbreak {
    // "jailbreak" this simulator's runtime (which carries over to all simulator devices based on this runtime)
    [self _performBlockOnCommandQueue:^{
        NSError *error = nil;
        if (!self.isBooted) {
            error = [NSError errorWithDomain:@"EABootedSimDevice" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Device is not booted"}];
        }
        else if ([self isJailbroken]) {
            error = [NSError errorWithDomain:@"EABootedSimDevice" code:2 userInfo:@{NSLocalizedDescriptionKey: @"Device is already jailbroken"}];
        }
        else if ([self prepareJbFilesystem] == NO) {
            error = [NSError errorWithDomain:@"EABootedSimDevice" code:3 userInfo:@{NSLocalizedDescriptionKey: @"Failed to prepare filesystem for jailbreak"}];
        }
        else if ([self setupInjection] == NO) {
            error = [NSError errorWithDomain:@"EABootedSimDevice" code:4 userInfo:@{NSLocalizedDescriptionKey: @"Failed to setup injection"}];
        }
        else if ([self hasInjection] == NO) {
            error = [NSError errorWithDomain:@"EABootedSimDevice" code:5 userInfo:@{NSLocalizedDescriptionKey: @"Failed to inject loader"}];
        }
        
        if (error) {
            NSLog(@"Failed to jailbreak device %@ with error: %@", self, error);
        }

        if (self.delegate && [self.delegate respondsToSelector:@selector(device:jailbreakFinished:error:)]) {
            BOOL success = [self isJailbroken];
            [self.delegate device:self jailbreakFinished:success error:error];
        }
    }];
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
                [self.delegate device:self didFailToShutdownWithError:[NSError errorWithDomain:@"EASimDevice" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Failed to shutdown device"}]];
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

- (BOOL)isJailbroken {
    return [self hasOverlays] || [self hasInjection];
}

@end
