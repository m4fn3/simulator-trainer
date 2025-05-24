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

- (NSString * _Nonnull)tweakLoaderDylibPath;
- (NSArray <NSString *> *)directoriesToOverlay;
- (NSDictionary *)bootstrapFilesToCopy;
- (BOOL)isJailbroken;
- (void)reboot;
- (void)respring;
- (void)shutdownWithCompletion:(void (^ _Nullable)(NSError *error))completion;

@end

NS_ASSUME_NONNULL_END
