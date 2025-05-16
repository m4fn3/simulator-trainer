//
//  EASimDevice.m
//  simulator-trainer
//
//  Created by Ethan Arbuckle on 4/28/25.
//

#import "EASimDevice.h"
#import "EAXCRun.h"
#import "CommandRunner.h"
#import <objc/runtime.h>
#import <objc/message.h>

@interface EASimDevice () {
    dispatch_queue_t _commandQueue;
}
@end

static void printAllObjcMethods(id obj) {
    unsigned int instanceMethodCount = 0;
    Method *instanceMethods = class_copyMethodList([obj class], &instanceMethodCount);
    
    for (unsigned int i = 0; i < instanceMethodCount; i++) {
        Method method = instanceMethods[i];
        SEL selector = method_getName(method);
        const char *name = sel_getName(selector);
        printf("-%s;\n", name);
    }
    
    free(instanceMethods);
    
    unsigned int classMethodCount = 0;
    Class cls = [obj class];
    Class superClass = class_getSuperclass(cls);
    while (superClass) {
        Method *classMethods = class_copyMethodList(superClass, &classMethodCount);
        
        for (unsigned int i = 0; i < classMethodCount; i++) {
            Method method = classMethods[i];
            SEL selector = method_getName(method);
            const char *name = sel_getName(selector);
            printf("+%s;\n", name);
        }
        
        free(classMethods);
        superClass = class_getSuperclass(superClass);
    }
    
    unsigned int protocolCount = 0;
    Protocol * __unsafe_unretained *protocols = class_copyProtocolList([obj class], &protocolCount);
    for (unsigned int i = 0; i < protocolCount; i++) {
        Protocol *protocol = protocols[i];
        const char *name = protocol_getName(protocol);
        printf("@ %s\n", name);
        
        unsigned int methodCount = 0;
        struct objc_method_description *methods = protocol_copyMethodDescriptionList(protocol, YES, YES, &methodCount);
        for (unsigned int j = 0; j < methodCount; j++) {
            struct objc_method_description method = methods[j];
            const char *name = sel_getName(method.name);
            printf("  - %s\n", name);
        }
        free(methods);
        
    }
    
    free(protocols);
    
    unsigned int ivarCount = 0;
    Ivar *ivars = class_copyIvarList([obj class], &ivarCount);
    
    for (unsigned int i = 0; i < ivarCount; i++) {
        
        Ivar ivar = ivars[i];
        const char *name = ivar_getName(ivar);
        const char *type = ivar_getTypeEncoding(ivar);
        @try {
            NSString *ivarStringValue = [NSString stringWithFormat:@"%@", [obj valueForKey:[NSString stringWithUTF8String:name]]];
            printf("  @ivar %s: %s = %s\n", name, type, ivarStringValue.UTF8String);
        }
        @catch (NSException *exception) {
        }        
    }
    free(ivars);
    
    unsigned int propertyCount = 0;
    objc_property_t *properties = class_copyPropertyList([obj class], &propertyCount);
    for (unsigned int i = 0; i < propertyCount; i++) {
        objc_property_t property = properties[i];
        const char *name = property_getName(property);
        const char *attributes = property_getAttributes(property);
        @try {
            NSString *propertyStringValue = [NSString stringWithFormat:@"%@", [obj valueForKey:[NSString stringWithUTF8String:name]]];
            printf("  @property %s: %s = %s\n", name, attributes, propertyStringValue.UTF8String);
        }
        @catch (NSException *exception) {
        }
    }
    free(properties);
}
    
@implementation EASimDevice

- (instancetype)initWithDict:(NSDictionary *)simInfoDict {
    if (!simInfoDict) {
        NSLog(@"Attempted to create EASimDevice with nil simInfoDict");
        return nil;
    }
    
    if ((self = [super init])) {
        self.coreSimDevice = simInfoDict;
        _commandQueue = dispatch_queue_create("com.simulatortrainer.commandqueue", DISPATCH_QUEUE_SERIAL);
        
        NSString *state = ((id (*)(id, SEL))objc_msgSend)(simInfoDict, NSSelectorFromString(@"stateString"));
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
        NSLog(@"-runtimeRoot: Requesting runtime root but simInfoDict not found for device: %@", self);
        return nil;
    }
    
    id simruntime = ((id (*)(id, SEL))objc_msgSend)(self.coreSimDevice, NSSelectorFromString(@"runtime"));
    if (!simruntime) {
        NSLog(@"-runtimeRoot: Failed to get simruntime for device: %@", self);
        return nil;
    }
    
    NSURL *runtimeRootURL = ((id (*)(id, SEL))objc_msgSend)(simruntime, NSSelectorFromString(@"runtimeRootURL"));
    if (!runtimeRootURL) {
        NSLog(@"-runtimeRoot: Failed to get runtime root URL for device: %@", self);
        return nil;
    }
    
    return [runtimeRootURL path];
}

- (NSString *)dataRoot {
    return [self.coreSimDevice valueForKey:@"dataPath"];
}

- (NSString *)name {
    return ((id (*)(id, SEL))objc_msgSend)(self.coreSimDevice, NSSelectorFromString(@"name"));
}

- (NSString *)runtimeVersion {
    NSDictionary *runtime = [self.coreSimDevice valueForKey:@"runtime"];
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
