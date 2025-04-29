//
//  EASimulator.h
//  simulator-trainer
//
//  Created by Ethan Arbuckle on 4/28/25.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface EASimulator : NSObject

@property (nonatomic, copy) NSUUID *simUUID;

- (instancetype)initWithSimulatorUUID:(NSUUID *)uuid;

@end

NS_ASSUME_NONNULL_END
