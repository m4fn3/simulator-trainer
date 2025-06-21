//
//  SimulatorOrchestrationService.m
//  simulator-trainer
//
//  Created by m1book on 5/23/25.
//

#import "SimulatorOrchestrationService.h"
#import "SimInjectionOptions.h"

@interface SimulatorOrchestrationService ()
@property (nonatomic, strong, nonnull) HelperConnection *helperConnection;
@end

@implementation SimulatorOrchestrationService

- (nonnull id)initWithHelperConnection:(nonnull HelperConnection *)helperConnection {
    if ((self = [super init])) {
        _helperConnection = helperConnection;
    }
    
    return self;
}

- (void)bootDevice:(nonnull SimulatorWrapper *)device completion:(nonnull void (^)(BootedSimulatorWrapper * _Nullable __strong, NSError * _Nullable __strong))completion {
    if (!device) {
        if (completion) {
            completion(nil, [NSError errorWithDomain:NSCocoaErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey: @"Device cannot be nil."}]);
        }

       return;
    }
    
    if (device.isBooted) {
       BootedSimulatorWrapper *alreadyBootedSim = [BootedSimulatorWrapper fromSimulatorWrapper:device];
       if (alreadyBootedSim) {
           if (completion) {
               completion(alreadyBootedSim, nil);
           }
       }
       else {
           if (completion) {
               completion(nil, [NSError errorWithDomain:NSCocoaErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey: @"Device is already booted but failed to convert to BootedSimulatorWrapper"}]);
           }
       }

       return;
    }

    [device bootWithCompletion:^(NSError * _Nullable error) {
       if (error) {
           if (completion) {
               completion(nil, [NSError errorWithDomain:NSCocoaErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"Failed to boot device: %@", error]}]);
           }
       }
       else {
           BootedSimulatorWrapper *bootedSim = [BootedSimulatorWrapper fromSimulatorWrapper:device];
           completion(bootedSim, nil);
       }
    }];
}

- (void)shutdownDevice:(nonnull BootedSimulatorWrapper *)device completion:(nonnull void (^)(NSError * _Nullable __strong))completion {
    if (!device || !device.isBooted) {
        if (completion) {
            completion([NSError errorWithDomain:NSCocoaErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey: @"Device cannot be nil or off"}]);
        }

       return;
    }
    
    [device shutdownWithCompletion:^(NSError * _Nullable error) {
        if (completion) {
            completion(error);
        }
    }];
}

- (void)rebootDevice:(nonnull BootedSimulatorWrapper *)device completion:(nonnull void (^)(NSError * _Nullable __strong))completion {
    if (!device || !device.isBooted) {
        if (completion) {
            completion([NSError errorWithDomain:NSCocoaErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey: @"Device cannot be nil or off"}]);
        }

       return;
    }

    [self shutdownDevice:device completion:^(NSError * _Nullable shutdownError) {
        if (shutdownError) {
            if (completion) {
                completion([NSError errorWithDomain:NSCocoaErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"Failed to shutdown device: %@", shutdownError]}]);
            }

            return;
        }

        [self bootDevice:device completion:^(BootedSimulatorWrapper * _Nullable bootedDevice, NSError * _Nullable bootError) {
            if (completion) {
                completion(bootError);
            }
        }];
    }];
}

- (void)respringDevice:(nonnull BootedSimulatorWrapper *)device completion:(nonnull void (^)(NSError * _Nullable __strong))completion {
    if (!device || !device.isBooted) {
        if (completion) {
            completion([NSError errorWithDomain:NSCocoaErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey: @"Device cannot be nil or off"}]);
        }

       return;
    }

    [device respring];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (completion) {
            completion(nil);
        }
    });
}

- (void)applyJailbreakToDevice:(nonnull BootedSimulatorWrapper *)device completion:(nonnull void (^)(BOOL, NSError * _Nullable __strong))completion {
    if (!self.helperConnection) {
        if (completion) {
            completion(NO, [NSError errorWithDomain:NSCocoaErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey: @"Helper connection is not available"}]);
        }

        return;
    }
    
    if (!device || !device.isBooted || [device isJailbroken]) {
        if (completion) {
            completion(NO, [NSError errorWithDomain:NSCocoaErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey: @"Device needs to be booted and unmodified"}]);
        }
        
        return;
    }

    [self.helperConnection mountTmpfsOverlaysAtPaths:[device directoriesToOverlay] completion:^(NSError *mountError) {
        if (mountError) {
            if (completion) {
                completion(NO, [NSError errorWithDomain:NSCocoaErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"Failed to mount tmpfs overlays: %@", mountError]}]);
            }

            return;
        }

        SimInjectionOptions *options = [[SimInjectionOptions alloc] init];
        options.tweakLoaderDestinationPath = [device tweakLoaderDylibPath];
        options.victimPathForTweakLoader = [device libObjcPath];
        options.tweakLoaderSourcePath = [[NSBundle mainBundle] pathForResource:@"loader" ofType:@"dylib"];
        options.optoolPath = [[NSBundle mainBundle] pathForResource:@"optool" ofType:nil];
        options.filesToCopy = [device bootstrapFilesToCopy];
        
        [self.helperConnection setupTweakInjectionWithOptions:options completion:^(NSError *injectionError) {
            if (injectionError) {
                if (completion) {
                    completion(NO, [NSError errorWithDomain:NSCocoaErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"Failed to setup tweak injection: %@", injectionError]}]);
                }

                return;
            }

            [device reloadDeviceState];
            if ([device isJailbroken]) {
                [self respringDevice:device completion:^(NSError * _Nullable respringError) {
                    if (respringError) {
                         NSLog(@"Jailbreak applied, but respring might have an issue: %@", respringError);
                    }
                    
                    if (completion) {
                        completion(YES, nil);
                    }
                }];
            }
            else {
                if (completion) {
                    completion(NO, [NSError errorWithDomain:NSCocoaErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey:@"No errors but it didn't work"}]);
                }
            }
        }];
    }];
}

- (void)removeJailbreakFromDevice:(nonnull BootedSimulatorWrapper *)device completion:(nonnull void (^)(BOOL, NSError * _Nullable __strong))completion {
    if (!device || !device.isJailbroken) {
        if (completion) {
            completion(NO, [NSError errorWithDomain:NSCocoaErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey: @"Device cannot be nil or unjailbroken"}]);
        }
        
        return;
    }
    
    [self.helperConnection unmountMountPoints:[device directoriesToOverlay] completion:^(NSError *unmountError) {
        if (unmountError) {
            NSLog(@"Failed to unmount mount points: %@", unmountError);
            // Don't fail
        }
        
        if (!device.isBooted) {
            completion(YES, nil);
            return;
        }
        
        [self shutdownDevice:device completion:^(NSError * _Nullable shutdownError) {
            if (shutdownError) {
                if (completion) {
                    completion(NO, [NSError errorWithDomain:NSCocoaErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"Failed to shutdown device: %@", shutdownError]}]);
                }
                
                return;
            }
            
            [self bootDevice:device completion:^(BootedSimulatorWrapper * _Nullable bootedDevice, NSError * _Nullable bootError) {
                [bootedDevice reloadDeviceState];

                if (bootError) {
                    if (completion) {
                        completion(NO, [NSError errorWithDomain:NSCocoaErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"Failed to boot device after jailbreak removal: %@", bootError]}]);
                    }
                }
                else {
                    BOOL success = bootedDevice.isJailbroken == NO;
                    NSError *isJailbrokenError = nil;
                    if (!success) {
                        isJailbrokenError = [NSError errorWithDomain:NSCocoaErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey:@"Device still reports as jailbroken after removal"}];
                    }
                    
                    completion(success, isJailbrokenError);
                }
            }];
        }];
    }];
}

@end
