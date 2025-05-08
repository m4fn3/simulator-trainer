//
//  EABootedSimDevice.h
//  simulator-trainer
//
//  Created by Ethan Arbuckle on 4/28/25.
//

#import <Cocoa/Cocoa.h>
#import "EASimDevice.h"

NS_ASSUME_NONNULL_BEGIN

@interface EABootedSimDevice : EASimDevice

+ (EABootedSimDevice *)fromSimDevice:(EASimDevice *)simDevice;
+ (EABootedSimDevice  * _Nullable)bootedDevice;
+ (NSArray <EABootedSimDevice *> *)allBootedDevices;
+ (NSArray <EASimDevice *> *)allDevices;

- (NSString *)invokeAndWait:(NSArray<NSString *> *)simCmdArgs;
- (BOOL)setupMounts;
- (void)unmountNow;
- (BOOL)hasOverlays;
- (BOOL)hasInjection;
- (void)setupInjection;
- (NSString *)pathToLoaderDylib;
- (void)unjailbreak;

- (void)shutdown;
- (void)reboot;

@end

NS_ASSUME_NONNULL_END
