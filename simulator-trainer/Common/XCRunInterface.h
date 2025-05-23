//
//  EAXCRun.h
//  simulator-trainer
//
//  Created by Ethan Arbuckle on 4/28/25.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface XCRunInterface : NSObject

+ (instancetype)sharedInstance;

- (NSString * _Nullable)xcrunInvokeAndWait:(NSArray<NSString *> *)arguments;
- (NSDictionary * _Nullable)coreSimulatorDeviceForUdid:(NSString *)udid;

@end

NS_ASSUME_NONNULL_END
