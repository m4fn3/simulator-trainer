//
//  BootedSimulatorWrapper.h
//  simulator-trainer
//
//  Created by Ethan Arbuckle on 4/28/25.
//

#import <Cocoa/Cocoa.h>
#import "SimulatorWrapper.h"

NS_ASSUME_NONNULL_BEGIN

@interface BootedSimulatorWrapper : SimulatorWrapper

@property (nonatomic) BOOL pendingReboot;

+ (BootedSimulatorWrapper * _Nullable)fromSimulatorWrapper:(SimulatorWrapper * _Nonnull)simDevice;

- (NSString *)invokeAndWait:(NSArray<NSString *> *)simCmdArgs;
- (BOOL)hasOverlays;
- (BOOL)hasInjection;
- (NSString * _Nonnull)tweakLoaderDylibPath;
- (NSArray <NSString *> *)directoriesToOverlay;
- (BOOL)isJailbroken;

- (void)shutdownWithCompletion:(void (^ _Nullable)(NSError *error))completion;
- (void)reboot;
- (void)respring;

- (NSDictionary *)bootstrapFilesToCopy;

@end

NS_ASSUME_NONNULL_END
