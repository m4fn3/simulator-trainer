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

@property (nonatomic) BOOL pendingReboot;

+ (EABootedSimDevice * _Nullable)fromSimDevice:(EASimDevice * _Nonnull)simDevice;
+ (NSArray <EASimDevice *> *)allDevices;

- (NSString *)invokeAndWait:(NSArray<NSString *> *)simCmdArgs;
- (BOOL)prepareJbFilesystem;
- (void)unmountNow;
- (BOOL)hasOverlays;
- (BOOL)hasInjection;
- (BOOL)setupInjection;
- (NSString * _Nonnull)pathToLoaderDylib;
- (void)unjailbreak;
- (void)jailbreak;
- (BOOL)isJailbroken;

- (void)shutdownWithCompletion:(void (^ _Nullable)(NSError *error))completion;
- (void)reboot;

@end

NS_ASSUME_NONNULL_END
