//
//  BootedSimulatorWrapper.m
//  simulator-trainer
//
//  Created by Ethan Arbuckle on 4/28/25.
//

#import <objc/message.h>
#import "BootedSimulatorWrapper.h"
#import "CommandRunner.h"
#import "tmpfs_overlay.h"

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


- (instancetype)initWithCoreSimDevice:(NSDictionary *)coreSimDevice {
    if ((self = [super initWithCoreSimDevice:coreSimDevice])) {
        self.pendingReboot = NO;
    }
    
    return self;
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
        @"cycript_server.dylib": @"/Library/MobileSubstrate/DynamicLibraries/cyript_server.dylib",
        @"cycript_server.plist": @"/Library/MobileSubstrate/DynamicLibraries/cyript_server.plist",
        @"libcycript.dylib": @"/usr/lib/libcycript.dylib",
        @"libcycript.db": @"/usr/lib/libcycript.db",
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
    NSString *otoolOutput = [CommandRunner xcrunInvokeAndWait:@[@"otool", @"-l", libPath]];
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
    [CommandRunner runCommand:@"/usr/bin/killall" withArguments:@[@"-9", @"backboardd"] stdoutString:nil error:nil];
}

- (BOOL)isJailbroken {
    return [self hasOverlays] || [self hasInjection];
}

@end
