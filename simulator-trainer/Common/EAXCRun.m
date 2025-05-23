//
//  EAXCRun.m
//  simulator-trainer
//
//  Created by Ethan Arbuckle on 4/28/25.
//

#import <objc/message.h>
#import "EABootedSimDevice.h"
#import "AppBinaryPatcher.h"
#import "EAXCRun.h"

@implementation EAXCRun

+ (instancetype)sharedInstance {
    static EAXCRun *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (NSString *)xcrunInvokeAndWait:(NSArray<NSString *> *)arguments {
    return [self _runXCRunCommand:arguments environment:nil waitUntilExit:YES];
}

- (NSDictionary *)coreSimulatorDeviceForUdid:(NSString *)targetUdid{
    NSArray *coreSimDevices = [EABootedSimDevice coreSimulatorDevices];
    for (int i = 0; i < coreSimDevices.count; i++) {
        NSDictionary *coreSimDevice = coreSimDevices[i];
        NSString *deviceUdid = [((NSUUID * (*)(id, SEL))objc_msgSend)(coreSimDevice, NSSelectorFromString(@"UDID")) UUIDString];
        if ([deviceUdid isEqualToString:targetUdid]) {
            return coreSimDevice;
        }
    }
    
    return nil;
}
    
- (NSString *)_runXCRunCommand:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)customEnvironment waitUntilExit:(BOOL)waitUntilExit {
    NSPipe *outputPipe = [NSPipe pipe];
    NSFileHandle *outputHandle = outputPipe.fileHandleForReading;

    NSDictionary *environDict = [[NSProcessInfo processInfo] environment];

    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath:@"/usr/bin/xcrun"];
    [task setArguments:arguments];
    [task setStandardOutput:outputPipe];
    [task setStandardError:outputPipe];
    
    if (customEnvironment) {
        NSMutableDictionary *mutableEnvironDict = [NSMutableDictionary dictionaryWithDictionary:environDict];
        [mutableEnvironDict addEntriesFromDictionary:customEnvironment];
        environDict = mutableEnvironDict;
    }
    [task setEnvironment:environDict];
    
    [task launch];
    
    if (waitUntilExit) {
        [task waitUntilExit];
        NSData *outputData = [outputHandle readDataToEndOfFile];
        return [[NSString alloc] initWithData:outputData encoding:NSUTF8StringEncoding];
    }

    return nil;
}

@end
    
