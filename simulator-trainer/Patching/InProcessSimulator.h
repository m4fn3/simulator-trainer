//
//  InProcessSimulator.h
//  simulator-trainer
//
//  Created by m1book on 5/28/25.
//

#import <Foundation/Foundation.h>

@interface InProcessSimulator : NSObject

@property (nonatomic, strong) id simulatorDelegate;

+ (instancetype)setup;

@end
