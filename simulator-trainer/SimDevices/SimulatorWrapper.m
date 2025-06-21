//
//  SimulatorWrapper.m
//  simulator-trainer
//
//  Created by Ethan Arbuckle on 4/28/25.
//

#import <objc/runtime.h>
#import <objc/message.h>
#import "SimulatorWrapper.h"
#import "SimDeviceManager.h"

@interface SimulatorWrapper ()
@end

@implementation SimulatorWrapper

- (instancetype)initWithCoreSimDevice:(id)coreSimDevice {
    if (!coreSimDevice) {
        NSLog(@"initWithCoreSimDevice: Attempted to create SimulatorWrapper with nil coreSimDevice");
        return nil;
    }
    
    if ((self = [super init])) {
        self.coreSimDevice = coreSimDevice;
    }
    
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@ booted:%d udid:%@>", NSStringFromClass(self.class), self.isBooted, self.udidString];
}

- (NSString *)debugDescription {
    return [NSString stringWithFormat:@"<%@ %p booted:%d, %@>", NSStringFromClass(self.class), self, self.isBooted, self.coreSimDevice];
}

- (BOOL)isEqual:(id)object {
    if (![object isKindOfClass:[SimulatorWrapper class]]) {
        return NO;
    }
    
    SimulatorWrapper *other = (SimulatorWrapper *)object;
    return [self.udidString isEqualToString:other.udidString];
}

- (BOOL)isBooted {
    if (!self.coreSimDevice) {
        NSLog(@"-isBooted: Requesting boot state but coreSimDevice not found for device: %@", self);
        return NO;
    }
    
    NSString *state = ((id (*)(id, SEL))objc_msgSend)(self.coreSimDevice, NSSelectorFromString(@"stateString"));
    if (!state) {
        NSLog(@"-isBooted: Failed to get state for device: %@", self);
        return NO;
    }

    return [state isEqualToString:@"Booted"];
}

- (NSString *)displayString {
    NSString *deviceLabel = [NSString stringWithFormat:@"   %@ (%@)", [self name], [self udidString]];
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
    
    id runtime = ((id (*)(id, SEL))objc_msgSend)(self.coreSimDevice, NSSelectorFromString(@"runtime"));
    if (!runtime) {
        NSLog(@"-runtimeRoot: Failed to get simruntime for device: %@", self);
        return nil;
    }

    return ((id (*)(id, SEL))objc_msgSend)(runtime, NSSelectorFromString(@"root"));
}

- (NSString *)name {
    return ((id (*)(id, SEL))objc_msgSend)(self.coreSimDevice, NSSelectorFromString(@"descriptiveName"));
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
    id runtime = ((id (*)(id, SEL))objc_msgSend)(self.coreSimDevice, NSSelectorFromString(@"runtime"));
    if (!runtime) {
        NSLog(@"-platform: Failed to get simruntime for device: %@", self);
        return nil;
    }
    
    return ((id (*)(id, SEL))objc_msgSend)(runtime, NSSelectorFromString(@"shortName"));
}

- (void)reloadDeviceState {
    self.coreSimDevice = [SimDeviceManager coreSimulatorDeviceForUdid:self.udidString];
    if (!self.coreSimDevice) {
        NSLog(@"Failed to reload device state for device: %@", self);
        return;
    }
}

- (void)bootWithCompletion:(void (^ _Nullable)(NSError * _Nullable error))completion {
    if (!self.coreSimDevice) {
        if (completion) {
            completion([NSError errorWithDomain:NSCocoaErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey: @"coreSimDevice is nil"}]);
        }
        else {
            NSLog(@"Attempted to boot device with nil coreSimDevice: %@", self);
        }
        return;
    }
    
    if (self.isBooted) {
        [self reloadDeviceState];

        if (self.isBooted) {

            NSError *error = [NSError errorWithDomain:NSCocoaErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey: @"Device is already booted"}];
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
    if ([self isKindOfClass:NSClassFromString(@"BootedSimulatorWrapper")]) {
        bootingForReboot = [[self valueForKey:@"pendingReboot"] boolValue];
        // Clear pending reboot flag regardless of whether boot failed or not
        [self setValue:@(NO) forKey:@"pendingReboot"];
    }
    
    // Begin boot
    NSDictionary *options = @{};
    dispatch_queue_t completionQueue = dispatch_queue_create("com.simulatortrainer.bootcompletion", DISPATCH_QUEUE_SERIAL);
    ((void (*)(id, SEL, id, id, id))objc_msgSend)(self.coreSimDevice, NSSelectorFromString(@"bootAsyncWithOptions:completionQueue:completionHandler:"), options, completionQueue, ^(NSError *error) {
        // Boot completed. Refresh the device state, check for errors, then notify the delegate/completionHandler
        [self reloadDeviceState];
        
        if (error) {
            if (self.delegate && [self.delegate respondsToSelector:@selector(device:didFailToBootWithError:)]) {
                [self.delegate device:self didFailToBootWithError:error];
            }
            
            if (completion) {
                completion(error);
            }
        }
        else {
            // Done booting (or failed to boot), notify the delegate if needed.
            if (bootingForReboot && [self.delegate respondsToSelector:@selector(deviceDidReboot:)]) {
                // Reboot-boots fire a different delegate method
                [self.delegate deviceDidReboot:self];
            }
            else if (!bootingForReboot && self.isBooted && [self.delegate respondsToSelector:@selector(deviceDidBoot:)]) {
                // Device is booted
                SimulatorWrapper *bootedDevice = ((id (*)(id, SEL, id))objc_msgSend)(NSClassFromString(@"BootedSimulatorWrapper"), NSSelectorFromString(@"fromSimulatorWrapper:"), self);
                [self.delegate deviceDidBoot:bootedDevice];
            }
            else if (!bootingForReboot && !self.isBooted && [self.delegate respondsToSelector:@selector(device:didFailToBootWithError:)]) {
                // Device was booting, but failed to boot
                [self.delegate deviceDidBoot:self];
            }
            else if (!self.isBooted && [self.delegate respondsToSelector:@selector(device:didFailToBootWithError:)]) {
                // No errors were raised, but the device remains unbooted
                [self.delegate device:self didFailToBootWithError:[NSError errorWithDomain:NSCocoaErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey: @"Device failed to boot"}]];
            }
        }
        
        if (completion) {
            if (self.isBooted) {
                completion(nil);
            }
            else {
                completion([NSError errorWithDomain:NSCocoaErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey: @"Failed to boot device"}]);
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
