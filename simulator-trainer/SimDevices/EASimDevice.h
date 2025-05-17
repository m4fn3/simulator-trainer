//
//  EASimDevice.h
//  simulator-trainer
//
//  Created by Ethan Arbuckle on 4/28/25.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class EASimDevice;
@protocol EASimDeviceDelegate <NSObject>

@optional
- (void)deviceDidBoot:(EASimDevice *)simDevice;
- (void)deviceDidShutdown:(EASimDevice *)simDevice;
- (void)deviceDidReboot:(EASimDevice *)simDevice;
- (void)device:(EASimDevice *)simDevice didFailToBootWithError:(NSError * _Nullable)error;
- (void)device:(EASimDevice *)simDevice didFailToShutdownWithError:(NSError * _Nullable)error;
- (void)device:(EASimDevice *)simDevice jailbreakFinished:(BOOL)success error:(NSError * _Nullable)error;

@end

@interface EASimDevice : NSObject

@property (nonatomic, weak) id<EASimDeviceDelegate> delegate;
@property (nonatomic) BOOL isBooted;
@property (nonatomic, strong) id coreSimDevice;

- (instancetype)initWithCoreSimDevice:(id)coreSimDevice;

- (void)_performBlockOnCommandQueue:(dispatch_block_t)block;

- (NSString *)displayString;
- (NSString *)udidString;
- (NSString *)runtimeRoot;
- (NSString *)dataRoot;
- (NSString *)name;
- (NSString *)runtimeVersion;
- (NSString *)platform;

- (void)reloadDeviceState;
- (void)boot;

@end

NS_ASSUME_NONNULL_END
