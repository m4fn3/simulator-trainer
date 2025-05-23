//
//  SimDeviceManager.h
//  simulator-trainer
//
//  Created by m1book on 5/23/25.
//

#import <Foundation/Foundation.h>
#import "SimulatorWrapper.h"

NS_ASSUME_NONNULL_BEGIN

@interface SimDeviceManager : NSObject

+ (NSArray <id> * _Nullable)coreSimulatorDevices;
+ (NSArray <SimulatorWrapper *> * _Nonnull)buildDeviceList;
+ (id _Nullable)coreSimulatorDeviceForUdid:(NSString *)targetUdid;

@end

NS_ASSUME_NONNULL_END
