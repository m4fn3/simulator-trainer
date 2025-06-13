//
//  InProcessSimulator.h
//  simulator-trainer
//
//  Created by m1book on 5/28/25.
//

#import <Foundation/Foundation.h>

@class BootedSimulatorWrapper;
@interface InProcessSimulator : NSObject

@property (nonatomic, readonly) id simulatorDelegate;

+ (instancetype)sharedSetupIfNeeded;

- (void)traceLaunchBundleId:(NSString *)bundleId withTracePattern:(NSString *)pattern;
- (void)focusSimulatorDevice:(BootedSimulatorWrapper *)device;

@end
