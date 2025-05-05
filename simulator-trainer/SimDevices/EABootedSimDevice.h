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

+ (EABootedSimDevice  * _Nullable)bootedDevice;
+ (NSArray <EABootedSimDevice *> *)allBootedDevices;

- (NSString *)invokeAndWait:(NSArray<NSString *> *)simCmdArgs;
- (BOOL)setupMounts;
- (void)unmountNow;
- (BOOL)hasOverlays;
- (BOOL)hasInjection;
- (void)setupInjection;
- (NSString *)pathToLoaderDylib;
- (void)unjailbreak;

@end

NS_ASSUME_NONNULL_END
