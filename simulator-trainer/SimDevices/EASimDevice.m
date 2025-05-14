//
//  EASimDevice.m
//  simulator-trainer
//
//  Created by Ethan Arbuckle on 4/28/25.
//

#import "EASimDevice.h"
#import "EAXCRun.h"
#import "CommandRunner.h"

@interface EASimDevice () {
    dispatch_queue_t _commandQueue;
}
@end

@implementation EASimDevice

- (instancetype)initWithDict:(NSDictionary *)simInfoDict {
    if (!simInfoDict) {
        NSLog(@"Attempted to create EASimDevice with nil simInfoDict");
        return nil;
    }
    
    if ((self = [super init])) {
        self.simInfoDict = simInfoDict;
        _commandQueue = dispatch_queue_create("com.simulatortrainer.commandqueue", DISPATCH_QUEUE_SERIAL);
        
        self.isBooted = [self.simInfoDict[@"state"] isEqualToString:@"Booted"];
    }
    
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@ booted:%d udid:%@>", NSStringFromClass(self.class), self.isBooted, self.udidString];
}

- (NSString *)debugDescription {
    return [NSString stringWithFormat:@"<%@ %p booted:%d, %@>", NSStringFromClass(self.class), self, self.isBooted, self.simInfoDict];
}

- (NSString *)displayString {
    NSString *deviceLabel = [NSString stringWithFormat:@"   %@ - %@ (%@)", [self name], [self platform], [self udidString]];
    if (self.isBooted) {
        deviceLabel = [@"(Booted) " stringByAppendingString:deviceLabel];
    }

    return deviceLabel;
}

- (NSString *)udidString {
    return [self.simInfoDict valueForKey:@"udid"];
}

- (NSString *)runtimeRoot {
    if (!self.simInfoDict) {
        NSLog(@"Requesting runtime root but simInfoDict not found for device: %@", self);
        return nil;
    }
    
    NSDictionary *runtime = [self.simInfoDict valueForKey:@"runtime"];
    if (!runtime) {
        [self reloadDeviceState];
        
        runtime = [self.simInfoDict valueForKey:@"runtime"];
    }
    
    if (!runtime) {
        NSLog(@"No runtime found for device: %@", self.simInfoDict);
        return nil;
    }
    
    return [runtime valueForKey:@"runtimeRoot"];
}

- (NSString *)dataRoot {
    return [self.simInfoDict valueForKey:@"dataPath"];
}

- (NSString *)name {
    return [self.simInfoDict valueForKey:@"name"];
}

- (NSString *)runtimeVersion {
    NSDictionary *runtime = [self.simInfoDict valueForKey:@"runtime"];
    return [runtime valueForKey:@"version"];
}

- (NSString *)platform {
    NSDictionary *runtime = [self.simInfoDict valueForKey:@"runtime"];
    return [runtime valueForKey:@"platform"];
}

- (void)reloadDeviceState {
    NSDictionary *runtime = [self.simInfoDict valueForKey:@"runtime"];
    NSDictionary *deviceInfo = [[EAXCRun sharedInstance] simDeviceInfoForUDID:self.udidString];
    if (!deviceInfo) {
        NSLog(@"Failed to refresh device status: %@", self);
        return;
    }
    
    NSMutableDictionary *updatedInfo = [deviceInfo mutableCopy];
    [updatedInfo setValue:runtime forKey:@"runtime"];
    [updatedInfo setValue:runtime[@"identifier"] forKey:@"runtimeIdentifier"];
    
    self.simInfoDict = updatedInfo;
    self.isBooted = [self.simInfoDict[@"state"] isEqualToString:@"Booted"];
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

- (void)boot {
    if (self.isBooted) {
        [self reloadDeviceState];
        
        if (self.isBooted) {
            NSLog(@"Device is already booted: %@", self);
            return;
        }
    }
    
    // todo: improve
    BOOL bootingForReboot = NO;
    if ([self isKindOfClass:NSClassFromString(@"EABootedSimDevice")]) {
        bootingForReboot = [self valueForKey:@"pendingReboot"];
    }

    [self _performBlockOnCommandQueue:^{
        [[EAXCRun sharedInstance] xcrunInvokeAndWait:@[@"simctl", @"boot", self.udidString]];
        
        NSError *error = nil;
        [CommandRunner runCommand:@"/usr/bin/open" withArguments:@[@"-a", @"Simulator"] stdoutString:nil error:&error];
        if (error) {
            NSLog(@"Simulator failed to open: %@", error.localizedDescription);
            return;
        }
        
        for (int i = 0; i < 3 && !self.isBooted; i++) {
            [self reloadDeviceState];
            if (self.isBooted) {
                break;
            }
            
            [NSThread sleepForTimeInterval:1.0];
        }
        
        // Done booting (or failed to boot)
        // Notify the delegate if needed
        if (self.delegate) {
            
            // If this was a reboot, reset the pendingReboot flag and notify the delegate
            if (bootingForReboot) {
                [self setValue:@(NO) forKey:@"pendingReboot"];
                
                if ([self.delegate respondsToSelector:@selector(deviceDidReboot:)]) {
                    [self.delegate deviceDidReboot:self];
                }
                
                return;
            }
            
            // Normal boot or failure
            if (self.isBooted && [self.delegate respondsToSelector:@selector(deviceDidBoot:)]) {
                [self.delegate deviceDidBoot:self];
            }
            else if (!self.isBooted && [self.delegate respondsToSelector:@selector(device:didFailToBootWithError:)]) {
                [self.delegate device:self didFailToBootWithError:[NSError errorWithDomain:@"EASimDevice" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Failed to boot device"}]];
            }
        }
    }];
}

@end
