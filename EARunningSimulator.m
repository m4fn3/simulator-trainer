//
//  EARunningSimulator.m
//  simulator-trainer
//
//  Created by Ethan Arbuckle on 4/28/25.
//

#import "EARunningSimulator.h"
#import "EAXCRun.h"

@implementation EARunningSimulator

+ (EARunningSimulator *)runningSimulator {
    
    BOOL onlyBooted = YES;
    NSArray *sims = getSimulatorDevices(onlyBooted);
    for (id sim in sims) {
        NSLog(@"%@\n\n\n\n\n", sim);
    }
    
    return nil;
}

@end
