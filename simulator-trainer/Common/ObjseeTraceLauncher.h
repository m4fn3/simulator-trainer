//
//  ObjseeTraceLauncher.h
//  simulator-trainer
//
//  Created by m1book on 6/21/25.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ObjseeTraceRequest : NSObject
@property (nonatomic, strong) NSString *targetBundleId;
@property (nonatomic, strong) NSString *targetDeviceId;
@property (nonatomic, strong) NSArray *classPatterns;
@property (nonatomic, strong) NSArray *methodPatterns;
@property (nonatomic, strong) NSArray *imagePatterns;
@end

@interface ObjseeTraceLauncher : NSObject

+ (instancetype)sharedInstance;

- (void)startTracingWithRequest:(ObjseeTraceRequest *)request;

@end

NS_ASSUME_NONNULL_END
