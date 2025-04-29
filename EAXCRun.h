//
//  EAXCRun.h
//  simulator-trainer
//
//  Created by Ethan Arbuckle on 4/28/25.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface EAXCRun : NSObject

@end

NSArray *getSimulatorDevices(BOOL onlyBooted);

NS_ASSUME_NONNULL_END
