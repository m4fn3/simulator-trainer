//
//  SimDeviceManager.m
//  simulator-trainer
//
//  Created by m1book on 5/23/25.
//

#import <objc/runtime.h>
#import <objc/message.h>
#import "SimDeviceManager.h"
#import "BootedSimulatorWrapper.h"

@implementation SimDeviceManager

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

+ (NSArray <SimulatorWrapper *> *)buildDeviceList {
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
                device = [[BootedSimulatorWrapper alloc] initWithCoreSimDevice:coreSimDevice];
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

+ (id)coreSimulatorDeviceForUdid:(NSString *)targetUdid {
    NSArray *coreSimDevices = [SimDeviceManager coreSimulatorDevices];
    for (int i = 0; i < coreSimDevices.count; i++) {
        NSDictionary *coreSimDevice = coreSimDevices[i];
        NSString *deviceUdid = [((NSUUID * (*)(id, SEL))objc_msgSend)(coreSimDevice, NSSelectorFromString(@"UDID")) UUIDString];
        if ([deviceUdid isEqualToString:targetUdid]) {
            return coreSimDevice;
        }
    }
    
    return nil;
}

@end
