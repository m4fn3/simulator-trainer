//
//  EASimDevice.m
//  simulator-trainer
//
//  Created by Ethan Arbuckle on 4/28/25.
//

#import <objc/runtime.h>
#import <objc/message.h>
#import "CommandRunner.h"
#import "EASimDevice.h"
#import "EAXCRun.h"

@interface EASimDevice () {
    dispatch_queue_t _commandQueue;
}
@end

@implementation EASimDevice

+ (instancetype)deviceWithUdid:(NSString *)udid {
    if (!udid) {
        NSLog(@"Attempted to create EASimDevice with nil UDID");
        return nil;
    }
    
    id coreSimDevice = [[EAXCRun sharedInstance] coreSimulatorDeviceForUdid:udid];
    if (!coreSimDevice) {
        NSLog(@"Failed to get coreSimDevice for UDID: %@", udid);
        return nil;
    }
    
    EASimDevice *device = [[self alloc] initWithCoreSimDevice:coreSimDevice];
    if (!device) {
        NSLog(@"Failed to create EASimDevice for UDID: %@", udid);
        return nil;
    }
    
    NSString *state = ((id (*)(id, SEL))objc_msgSend)(device, NSSelectorFromString(@"stateString"));
    if ([state isEqualToString:@"Booted"]) {
        EASimDevice *bootedDevice = ((id (*)(id, SEL, id))objc_msgSend)(NSClassFromString(@"EABootedSimDevice"), NSSelectorFromString(@"fromSimDevice:"), device);
        if (bootedDevice) {
            return bootedDevice;
        }
    }
    
    return device;
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
    self.coreSimDevice = [[EAXCRun sharedInstance] coreSimulatorDeviceForUdid:self.udidString];
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
    // Keep track of whether this is a reboot or a cold boot
    BOOL bootingForReboot = NO;
    if ([self isKindOfClass:NSClassFromString(@"EABootedSimDevice")]) {
        bootingForReboot = [[self valueForKey:@"pendingReboot"] boolValue];
        // Clear pending reboot flag regardless of whether boot failed or not
        [self setValue:@(NO) forKey:@"pendingReboot"];
    }
    
    // Begin boot
    NSDictionary *options = @{};
    ((void (*)(id, SEL, id, id, id))objc_msgSend)(self.coreSimDevice, NSSelectorFromString(@"bootAsyncWithOptions:completionQueue:completionHandler:"), options, _commandQueue, ^(NSError *error) {
        // Boot completed. Refresh the device state, check for errors, then notify the delegate/completionHandler
        [self reloadDeviceState];
        
        if (error) {
            NSLog(@"Boot failed with error: %@", error);
            if (self.delegate && [self.delegate respondsToSelector:@selector(device:didFailToBootWithError:)]) {
                [self.delegate device:self didFailToBootWithError:error];
            }
            
            if (completion) {
                completion(error);
            }
        }
        else {
            // Boot completed successfully
            
            // Open the simulator GUI app so the simruntime can't ghost. They will happily sneak-run in the bg all day invisible
            NSError *cmdError = nil;
            NSString *cmdOutput = nil;
            [CommandRunner runCommand:@"/usr/bin/open" withArguments:@[@"-a", @"Simulator"] stdoutString:&cmdOutput error:&cmdError];
            
            // Done booting (or failed to boot)
            // Notify the delegate if needed
            //            if (self.delegate || completion) {
            // Reboot-boots fire a different delegate method
            if (bootingForReboot && [self.delegate respondsToSelector:@selector(deviceDidReboot:)]) {
                // Device is rebooted
                [self.delegate deviceDidReboot:self];
            }
            else if (!bootingForReboot && self.isBooted && [self.delegate respondsToSelector:@selector(deviceDidBoot:)]) {
                // Device is booted
                EASimDevice *bootedDevice = ((id (*)(id, SEL, id))objc_msgSend)(NSClassFromString(@"EABootedSimDevice"), NSSelectorFromString(@"fromSimDevice:"), self);
                [self.delegate deviceDidBoot:bootedDevice];
            }
            else if (!bootingForReboot && !self.isBooted && [self.delegate respondsToSelector:@selector(device:didFailToBootWithError:)]) {
                // Device was booting, but failed to boot
                EASimDevice *bootedDevice = ((id (*)(id, SEL, id))objc_msgSend)(NSClassFromString(@"EABootedSimDevice"), NSSelectorFromString(@"fromSimDevice:"), self);
                [self.delegate deviceDidBoot:bootedDevice];
            }
            else if (!self.isBooted && [self.delegate respondsToSelector:@selector(device:didFailToBootWithError:)]) {
                // No errors were raised, but the device remains unbooted
            }
        }
        
        if (completion) {
            if (self.isBooted) {
                completion(nil);
            }
            else {
                completion([NSError errorWithDomain:@"EASimDevice" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Failed to boot device"}]);
            }
        }
    });
}

- (NSString *)libObjcPath {
    // This is the path to the binary/dylib that the tweak loader dylib will be
    // injected into as a load command. Anything that uses this will also
    // get the tweak loader injected.
    
    // RUNTIME_ROOT/usr/lib/libobjc.A.dylib
    NSString *libObjcPath = @"/usr/lib/libobjc.A.dylib";
    return [self.runtimeRoot stringByAppendingPathComponent:libObjcPath];
}

@end
