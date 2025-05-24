//
//  SimulatorOrchestrationService.h
//  simulator-trainer
//
//  Created by m1book on 5/23/25.
//

#import <Foundation/Foundation.h>
#import "HelperConnection.h"
#import "SimulatorWrapper.h"
#import "BootedSimulatorWrapper.h"

NS_ASSUME_NONNULL_BEGIN

@interface SimulatorOrchestrationService : NSObject

- (id)initWithHelperConnection:(HelperConnection *)helperConnection;

- (void)bootDevice:(SimulatorWrapper *)device completion:(void (^)(BootedSimulatorWrapper * _Nullable bootedDevice, NSError * _Nullable error))completion;
- (void)shutdownDevice:(BootedSimulatorWrapper *)device completion:(void (^)(NSError * _Nullable error))completion;
- (void)rebootDevice:(BootedSimulatorWrapper *)device completion:(void (^)(NSError * _Nullable error))completion;
- (void)respringDevice:(BootedSimulatorWrapper *)device completion:(void (^)(NSError * _Nullable error))completion;
- (void)applyJailbreakToDevice:(BootedSimulatorWrapper *)device completion:(void (^)(BOOL success, NSError * _Nullable error))completion;
- (void)removeJailbreakFromDevice:(BootedSimulatorWrapper *)device completion:(void (^)(BOOL success, NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
