//
//  EASimDevice.m
//  simulator-trainer
//
//  Created by Ethan Arbuckle on 4/28/25.
//

#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import "CommandRunner.h"
#import "EASimDevice.h"
#import "EAXCRun.h"

// Filter out some of the spammy Simulator logs
const NSString *kSimLogIgnoreStrings[] = {
    @" is handling device added notification: ",
    @"-[SimDeviceSet addDeviceAsync:]:",
    @"On devices queue adding device",
    @" to _devicesByUDID for set ",
    @"VolumeManager: Appeared: Ignoring",
    @"Ignoring disk due to missing volume path.",
    @"Found duplicate SDKs for",
    @" New device pair (",
    @"Runtime bundle found. Adding to supported runtimes",
    @"VolumeManager: Disk Appeared <DADisk ",
};

static void _SimServiceLog(int level, const char *function, int line, NSString *format, va_list args) {
    if (!format) {
        return;
    }

    NSString *formattedString = [[NSString alloc] initWithFormat:format arguments:args];
    if (formattedString) {
        NSString *logString = [NSString stringWithFormat:@"%s:%d %@", function, line, formattedString];
        // Check if the log message contains any of the ignore strings.
        // This happens after building the message because some of the ignore-strings include function names
        for (int i = 0; i < sizeof(kSimLogIgnoreStrings) / sizeof(NSString *); i++) {
            if ([logString containsString:(NSString *)kSimLogIgnoreStrings[i]]) {
                return;
            }
        }
        
        NSLog(@"%@", logString);
    }
}

static void setup_logging(void) {
    // Register a logging handler for the Simulator. This will receive all logs regardless of their level
    void *coreSimHandle = dlopen("/Library/Developer/PrivateFrameworks/CoreSimulator.framework/Versions/A/CoreSimulator", RTLD_GLOBAL);
    void *_SimLogSetHandler = dlsym(coreSimHandle, "SimLogSetHandler");
    if (_SimLogSetHandler == NULL) {
        return;
    }
    
    ((void (*)(void *))_SimLogSetHandler)(_SimServiceLog);
}

@interface EASimDevice () {
    dispatch_queue_t _commandQueue;
}
@end

@implementation EASimDevice

+ (void)load {
    setup_logging();
}

- (instancetype)initWithCoreSimDevice:(id)coreSimDevice {
    if (!coreSimDevice) {
        NSLog(@"Attempted to create EASimDevice with nil coreSimDevice");
        return nil;
    }
    
    if ((self = [super init])) {
        self.coreSimDevice = coreSimDevice;
        _commandQueue = dispatch_queue_create("com.simulatortrainer.commandqueue", DISPATCH_QUEUE_SERIAL);
        
        NSString *state = ((id (*)(id, SEL))objc_msgSend)(self.coreSimDevice, NSSelectorFromString(@"stateString"));
        self.isBooted = [state isEqualToString:@"Booted"];
    }
    
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@ booted:%d udid:%@>", NSStringFromClass(self.class), self.isBooted, self.udidString];
}

- (NSString *)debugDescription {
    return [NSString stringWithFormat:@"<%@ %p booted:%d, %@>", NSStringFromClass(self.class), self, self.isBooted, self.coreSimDevice];
}

- (NSString *)displayString {
    NSString *deviceLabel = [NSString stringWithFormat:@"   %@ - %@ (%@)", [self name], [self platform], [self udidString]];
    if (self.isBooted) {
        deviceLabel = [@"(Booted) " stringByAppendingString:deviceLabel];
    }

    return deviceLabel;
}

- (NSString *)udidString {
    NSUUID *udidUUID = ((id (*)(id, SEL))objc_msgSend)(self.coreSimDevice, NSSelectorFromString(@"UDID"));
    if (!udidUUID) {
        NSLog(@"Failed to get UDID for device: %@", self);
        return nil;
    }
    
    return [udidUUID UUIDString];
}

- (NSString *)runtimeRoot {
    if (!self.coreSimDevice) {
        NSLog(@"-runtimeRoot: Requesting runtime root but coreSimDevice not found for device: %@", self);
        return nil;
    }
    
    id simruntime = ((id (*)(id, SEL))objc_msgSend)(self.coreSimDevice, NSSelectorFromString(@"runtime"));
    if (!simruntime) {
        NSLog(@"-runtimeRoot: Failed to get simruntime for device: %@", self);
        return nil;
    }
    
    id runtime = ((id (*)(id, SEL))objc_msgSend)(self.coreSimDevice, NSSelectorFromString(@"runtime"));
    return ((id (*)(id, SEL))objc_msgSend)(runtime, NSSelectorFromString(@"root"));
}

- (NSString *)name {
    return ((id (*)(id, SEL))objc_msgSend)(self.coreSimDevice, NSSelectorFromString(@"name"));
}

- (NSString *)runtimeVersion {
    NSDictionary *runtime = [self.coreSimDevice valueForKey:@"runtime"];
    if (!runtime) {
        NSLog(@"-runtimeVersion: Failed to get runtime for device: %@", self);
        return nil;
    }

    return [runtime valueForKey:@"version"];
}

- (NSString *)platform {
    id simruntime = ((id (*)(id, SEL))objc_msgSend)(self.coreSimDevice, NSSelectorFromString(@"runtime"));
    if (!simruntime) {
        NSLog(@"-platform: Failed to get simruntime for device: %@", self);
        return nil;
    }
    
    return ((id (*)(id, SEL))objc_msgSend)(simruntime, NSSelectorFromString(@"shortName"));
}

- (void)reloadDeviceState {
    self.coreSimDevice = [[EAXCRun sharedInstance] simDeviceInfoForUDID:self.udidString];
    if (!self.coreSimDevice) {
        NSLog(@"Failed to reload device state for device: %@", self);
        return;
    }

    self.isBooted = [((id (*)(id, SEL))objc_msgSend)(self.coreSimDevice, NSSelectorFromString(@"stateString")) isEqualToString:@"Booted"];
}

- (void)_performBlockOnCommandQueue:(dispatch_block_t)block {
    if (!block) {
        NSLog(@"Attempted to perform nil block on command queue");
        return;
    }
    
    dispatch_async(_commandQueue, ^{
        block();
    });
}

- (void)bootWithCompletion:(void (^ _Nullable)(NSError * _Nullable error))completion {
    if (!self.coreSimDevice) {
        if (completion) {
            completion([NSError errorWithDomain:@"EASimDevice" code:1 userInfo:@{NSLocalizedDescriptionKey: @"coreSimDevice is nil"}]);
        }
        else {
            NSLog(@"Attempted to boot device with nil coreSimDevice: %@", self);
        }
        return;
    }
    
    if (self.isBooted) {
        [self reloadDeviceState];

        if (self.isBooted) {

            NSError *error = [NSError errorWithDomain:@"EASimDevice" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Device is already booted"}];
            if (self.delegate && [self.delegate respondsToSelector:@selector(device:didFailToBootWithError:)]) {
                [self.delegate device:self didFailToBootWithError:error];
            }

            if (completion) {
                completion(error);
            }

            return;
        }
    }
    
    // todo: improve
    BOOL bootingForReboot = NO;
    if ([self isKindOfClass:NSClassFromString(@"EABootedSimDevice")]) {
        bootingForReboot = [[self valueForKey:@"pendingReboot"] boolValue];
    }
    
    // Options: deathPort, persist, env, disabled_jobs, binpref, runtime, device_type
    NSDictionary *options = @{};
    ((void (*)(id, SEL, id, id, id))objc_msgSend)(self.coreSimDevice, NSSelectorFromString(@"bootAsyncWithOptions:completionQueue:completionHandler:"), options, _commandQueue, ^(NSError *error) {
        if (error) {
            NSLog(@"Boot failed with error: %@", error);
            if (self.delegate && [self.delegate respondsToSelector:@selector(device:didFailToBootWithError:)]) {
                [self.delegate device:self didFailToBootWithError:error];
            }
            
            if (completion) {
                completion(error);
            }
            
            return;
        }
        
//        [[EAXCRun sharedInstance] xcrunInvokeAndWait:@[@"simctl", @"boot", self.udidString]];
        
//        NSError *cmdError = nil;
//        NSString *cmdOutput = nil;
//        [CommandRunner runCommand:@"/usr/bin/open" withArguments:@[@"-a", @"Simulator"] stdoutString:&cmdOutput error:&cmdError];
        [[EAXCRun sharedInstance] _runCommandAsUnprivilegedUser:@[@"/usr/bin/open", @"-a", @"Simulator"] environment:nil waitUntilExit:YES];
//        
////        if (cmdError) {
////            NSLog(@"Simulator failed to open: %@", cmdError);
//            
//            if (self.delegate && [self.delegate respondsToSelector:@selector(device:didFailToBootWithError:)]) {
//                [self.delegate device:self didFailToBootWithError:cmdError];
//            }
//            
//            if (completion) {
//                completion(cmdError);
//            }
//            
//            
////            return;
////        }
//        
        [self reloadDeviceState];
        
        // Done booting (or failed to boot)
        // Notify the delegate if needed
        if (self.delegate || completion) {
            
            // If this was a reboot, reset the pendingReboot flag and notify the delegate.
            if (bootingForReboot) {
                [self setValue:@(NO) forKey:@"pendingReboot"];
                
                if ([self.delegate respondsToSelector:@selector(deviceDidReboot:)]) {
                    [self.delegate deviceDidReboot:self];
                }
                
                return;
            }
            
            if (self.isBooted && [self.delegate respondsToSelector:@selector(deviceDidBoot:)]) {
                // Device is booted
                EASimDevice *bootedDevice = ((id (*)(id, SEL, id))objc_msgSend)(NSClassFromString(@"EABootedSimDevice"), NSSelectorFromString(@"fromSimDevice:"), self);
                [self.delegate deviceDidBoot:bootedDevice];
            }
            else if (!self.isBooted && [self.delegate respondsToSelector:@selector(device:didFailToBootWithError:)]) {
                // No errors were raised, but the device remains unbooted
                [self.delegate device:self didFailToBootWithError:[NSError errorWithDomain:@"EASimDevice" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Failed to boot device"}]];
            }
        }
        
        if (completion && self.isBooted) {
            // Device is booted
            completion(nil);
        }
        else if (completion && !self.isBooted) {
            // No errors were raised, but the device remains unbooted
            completion([NSError errorWithDomain:@"EASimDevice" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Failed to boot device"}]);
        }
    });
}

@end
