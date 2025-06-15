//
//  SimulatorWrapper.h
//  simulator-trainer
//
//  Created by Ethan Arbuckle on 4/28/25.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class SimulatorWrapper;
@protocol SimulatorWrapperDelegate <NSObject>

@optional
- (void)deviceDidBoot:(SimulatorWrapper *)simDevice;
- (void)deviceDidShutdown:(SimulatorWrapper *)simDevice;
- (void)deviceDidReboot:(SimulatorWrapper *)simDevice;
- (void)device:(SimulatorWrapper *)simDevice didFailToBootWithError:(NSError * _Nullable)error;
- (void)device:(SimulatorWrapper *)simDevice didFailToShutdownWithError:(NSError * _Nullable)error;
- (void)device:(SimulatorWrapper *)simDevice jailbreakFinished:(BOOL)success error:(NSError * _Nullable)error;

@end

@interface SimulatorWrapper : NSObject

@property (nonatomic, weak) id<SimulatorWrapperDelegate> delegate;
@property (nonatomic, strong) id coreSimDevice;

- (instancetype)initWithCoreSimDevice:(id)coreSimDevice;

- (BOOL)isBooted;
- (NSString * _Nonnull)displayString;
- (NSString * _Nullable)udidString;
- (NSString * _Nullable)runtimeRoot;
- (NSString * _Nonnull)name;
- (NSString * _Nullable)runtimeVersion;
- (NSString * _Nullable)platform;
- (NSString * _Nonnull)libObjcPath;

- (void)reloadDeviceState;

- (void)bootWithCompletion:(void (^ _Nullable)(NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
