//
//  EASimDevice.h
//  simulator-trainer
//
//  Created by Ethan Arbuckle on 4/28/25.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface EASimDevice : NSObject

@property (nonatomic, assign, getter=_determineIfBooted) BOOL isBooted;
@property (nonatomic, copy) NSDictionary *simInfoDict;

- (instancetype)initWithDict:(NSDictionary *)simInfoDict;
- (NSString *)udidString;
- (NSString *)runtimeRoot;
- (NSString *)dataRoot;
- (NSString *)name;
- (NSString *)runtimeVersion;
- (NSString *)platform;

@end

NS_ASSUME_NONNULL_END
