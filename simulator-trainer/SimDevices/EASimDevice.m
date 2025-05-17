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

static NSString *objcTypeToReadable(const char *type) {
    NSString *typeStr = [NSString stringWithUTF8String:type];
    if ([typeStr hasPrefix:@"@\""]) {
        typeStr = [typeStr substringWithRange:NSMakeRange(2, typeStr.length - 3)];
        return [NSString stringWithFormat:@"%@ *", typeStr];
    } else if ([typeStr isEqualToString:@"q"] || [typeStr isEqualToString:@"Q"]) {
        return @"NSInteger";
    } else if ([typeStr isEqualToString:@"i"] || [typeStr isEqualToString:@"I"]) {
        return @"int";
    } else if ([typeStr isEqualToString:@"f"]) {
        return @"float";
    } else if ([typeStr isEqualToString:@"d"]) {
        return @"double";
    } else if ([typeStr isEqualToString:@"B"]) {
        return @"BOOL";
    } else if ([typeStr hasPrefix:@"^"]) {
        return [NSString stringWithFormat:@"%@", typeStr];
    }
    return typeStr;
}

static void printObjcHeaderForObject(id obj) {
    Class cls = [obj class];
    printf("@interface %s : %s {\n", class_getName(cls), class_getName(class_getSuperclass(cls)));

    unsigned int ivarCount = 0;
    Ivar *ivars = class_copyIvarList(cls, &ivarCount);
    for (unsigned int i = 0; i < ivarCount; i++) {
        Ivar ivar = ivars[i];
        const char *name = ivar_getName(ivar);
        const char *type = ivar_getTypeEncoding(ivar);
        NSString *ivarTypeStr = objcTypeToReadable(type);
        @try {
            id value = [obj valueForKey:[NSString stringWithUTF8String:name]];
            NSString *valueDesc = [value description];
            valueDesc = [valueDesc stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
            printf("    %s %s; // %s\n", ivarTypeStr.UTF8String, name, valueDesc.UTF8String);
        }
        @catch (NSException *e) {
            printf("    %s %s; // (inaccessible)\n", ivarTypeStr.UTF8String, name);
        }
    }
    free(ivars);

    printf("}\n\n");

    unsigned int propertyCount = 0;
    objc_property_t *properties = class_copyPropertyList(cls, &propertyCount);
    for (unsigned int i = 0; i < propertyCount; i++) {
        objc_property_t property = properties[i];
        const char *name = property_getName(property);
        const char *attributes = property_getAttributes(property);

        NSArray *attrParts = [[NSString stringWithUTF8String:attributes] componentsSeparatedByString:@","];
        NSString *typePart = attrParts.firstObject;
        NSString *propertyTypeStr = objcTypeToReadable(typePart.UTF8String + 1);

        @try {
            id value = [obj valueForKey:[NSString stringWithUTF8String:name]];
            NSString *valueDesc = [value description];
            valueDesc = [valueDesc stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
            printf("@property %s %s; // %s\n", propertyTypeStr.UTF8String, name, valueDesc.UTF8String);
        }
        @catch (NSException *e) {
            printf("@property %s %s; // (inaccessible)\n", propertyTypeStr.UTF8String, name);
        }
    }
    free(properties);

    printf("\n");

    unsigned int instanceMethodCount = 0;
    Method *instanceMethods = class_copyMethodList(cls, &instanceMethodCount);
    for (unsigned int i = 0; i < instanceMethodCount; i++) {
        Method method = instanceMethods[i];
        SEL selector = method_getName(method);
        printf("- (void)%s;\n", sel_getName(selector));
    }
    free(instanceMethods);

    unsigned int classMethodCount = 0;
    Method *classMethods = class_copyMethodList(object_getClass(cls), &classMethodCount);
    for (unsigned int i = 0; i < classMethodCount; i++) {
        Method method = classMethods[i];
        SEL selector = method_getName(method);
        printf("+ (void)%s;\n", sel_getName(selector));
    }
    free(classMethods);

    printf("\n@end\n");
}

@implementation EASimDevice

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

- (void)boot {
    if (!self.coreSimDevice) {
        NSLog(@"Attempted to boot device with nil coreSimDevice");
        return;
    }
    
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
        bootingForReboot = [[self valueForKey:@"pendingReboot"] boolValue];
    }
    
    // Options: deathPort, persist, env, disabled_jobs, binpref, runtime, device_type
    NSDictionary *options = @{};
    ((void (*)(id, SEL, id, id, id))objc_msgSend)(self.coreSimDevice, NSSelectorFromString(@"bootAsyncWithOptions:completionQueue:completionHandler:"), options, _commandQueue, ^(NSError *error) {
        if (error) {
            NSLog(@"Boot failed with error: %@", error);
            return;
        }
        
        NSError *cmdError = nil;
        [CommandRunner runCommand:@"/usr/bin/open" withArguments:@[@"-a", @"Simulator"] stdoutString:nil error:&cmdError];
        if (cmdError) {
            NSLog(@"Simulator failed to open: %@", cmdError);
            return;
        }
        
        [self reloadDeviceState];
        
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
                EASimDevice *bootedDevice = ((id (*)(id, SEL, id))objc_msgSend)(NSClassFromString(@"EABootedSimDevice"), NSSelectorFromString(@"fromSimDevice:"), self);
                [self.delegate deviceDidBoot:bootedDevice];
            }
            else if (!self.isBooted && [self.delegate respondsToSelector:@selector(device:didFailToBootWithError:)]) {
                [self.delegate device:self didFailToBootWithError:[NSError errorWithDomain:@"EASimDevice" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Failed to boot device"}]];
            }
        }
    });
}

@end
