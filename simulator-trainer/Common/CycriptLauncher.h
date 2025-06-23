//
//  CycriptLauncher.h
//  simulator-trainer
//
//  Created by m1book on 6/3/25.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CycriptLaunchRequest : NSObject
@property (nonatomic, strong) NSString *targetDeviceId;
@property (nonatomic, strong) NSString *targetBundleId;
@property (nonatomic, strong) NSString *processName;
@property (nonatomic) NSInteger serverPort;
@end

@interface CycriptLauncher : NSObject
@property (nonatomic, strong) CycriptLaunchRequest *request;

- (id)initWithRequest:(CycriptLaunchRequest *)request;

- (BOOL)launch;

@end

NS_ASSUME_NONNULL_END
