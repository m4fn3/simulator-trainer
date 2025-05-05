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

+ (EABootedSimDevice *)bootedDevice {
    NSArray <EABootedSimDevice *> *runningSimulators = [EABootedSimDevice allBootedDevices];
    if (runningSimulators.count > 1) {
        NSLog(@"Multiple simulators are booted, choosing the first one. Running Sims: %@", runningSimulators);
    }
    
   return [runningSimulators firstObject];
}

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


- (NSArray <NSString *> *)_allOverlayMountPointPaths {
    return @[
        [self.runtimeRoot stringByAppendingPathComponent:@"/usr/lib/"],
    ];
}

- (void)unmountNow {
    for (NSString *overlayPath in [self _allOverlayMountPointPaths]) {
        if (unmount_if_mounted(overlayPath.UTF8String) != 0) {
            NSLog(@"Failed to unmount path: %@", overlayPath);
        }
    }
}

- (BOOL)setupMounts {
    for (NSString *overlayPath in [self _allOverlayMountPointPaths]) {
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
    
    return YES;
}

- (BOOL)hasOverlays {    
    NSString *libraryMountPath = [self.runtimeRoot stringByAppendingPathComponent:@"/usr/lib/"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:libraryMountPath]) {
        NSLog(@"simruntime does not have a `/usr/lib/` directory");
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
    [[AppBinaryPatcher new] injectDylib:simRelativeLoaderPath intoBinary:libPath completion:^(BOOL success, NSError *error) {
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
    NSString *runtimelLibraryDir = [self.runtimeRoot stringByAppendingPathComponent:@"/usr/lib"];
    return [runtimelLibraryDir stringByAppendingPathComponent:@"loader.dylib"];
}

- (void)unjailbreak {
    if ([self hasInjection]) {
        NSError *error = nil;
        [[NSFileManager defaultManager] removeItemAtPath:self.pathToLoaderDylib error:&error];
        if (error) {
            NSLog(@"Failed to remove the tweak loader. path: %@, error: %@", self.pathToLoaderDylib, error);
        }
    }
    
    if ([self hasOverlays]) {
        [self unmountNow];
    }
    
    [CommandRunner runCommand:@"/usr/bin/killall" withArguments:@[@"-9", @"backboardd"] stdoutString:nil error:nil];
}

@end
