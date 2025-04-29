//
//  EARunningSimulator.h
//  simulator-trainer
//
//  Created by Ethan Arbuckle on 4/28/25.
//

#import <Cocoa/Cocoa.h>
#import "EASimulator.h"

NS_ASSUME_NONNULL_BEGIN

@interface EARunningSimulator : EASimulator

+ (EARunningSimulator  * _Nullable)runningSimulator;

@end

NS_ASSUME_NONNULL_END
