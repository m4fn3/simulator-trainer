//
//  EASimulator.m
//  simulator-trainer
//
//  Created by Ethan Arbuckle on 4/28/25.
//

#import "EASimulator.h"

@implementation EASimulator

- (instancetype)initWithSimulatorUUID:(NSUUID *)uuid {
    
    if (!uuid) {
        [NSException raise:@"SimInitFailure" format:@"UUID cannot be nil"];
    }
    
    if ((self = [super init])) {
        
        self.simUUID = uuid;
    }
    
    return self;
}

@end
