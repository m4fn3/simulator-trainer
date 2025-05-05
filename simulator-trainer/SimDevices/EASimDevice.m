//
//  EASimDevice.m
//  simulator-trainer
//
//  Created by Ethan Arbuckle on 4/28/25.
//

#import "EASimDevice.h"

@implementation EASimDevice

- (instancetype)initWithDict:(NSDictionary *)simInfoDict {
    if (!simInfoDict) {
        NSLog(@"simInfoDict cannot be nil");
        return nil;
    }
    
    if ((self = [super init])) {
        self.simInfoDict = simInfoDict;
    }
    
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@ booted:%d udid:%@>", NSStringFromClass(self.class), self.isBooted, self.udidString];
}

- (NSString *)debugDescription {
    return [NSString stringWithFormat:@"<%@ %p booted:%d, %@>", NSStringFromClass(self.class), self, self.isBooted, self.simInfoDict];
}

- (BOOL)_determineIfBooted {
    if (!self.simInfoDict) {
        return NO;
    }
    
    NSString *deviceState = [self.simInfoDict valueForKey:@"state"];
    if (!deviceState) {
        NSLog(@"Invalid device state: %@", self);
        return NO;
    }
    
    return [deviceState isEqualToString:@"Booted"];
}

- (NSString *)udidString {
    return [self.simInfoDict valueForKey:@"udid"];
}

- (NSString *)runtimeRoot {
    NSDictionary *runtime = [self.simInfoDict valueForKey:@"runtime"];
    return [runtime valueForKey:@"runtimeRoot"];
}

- (NSString *)dataRoot {
    return [self.simInfoDict valueForKey:@"dataPath"];
}

- (NSString *)name {
    return [self.simInfoDict valueForKey:@"name"];
}

- (NSString *)runtimeVersion {
    NSDictionary *runtime = [self.simInfoDict valueForKey:@"runtime"];
    return [runtime valueForKey:@"version"];
}

- (NSString *)platform {
    NSDictionary *runtime = [self.simInfoDict valueForKey:@"runtime"];
    return [runtime valueForKey:@"platform"];
}

@end
