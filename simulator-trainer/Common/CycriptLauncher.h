//
//  CycriptLauncher.h
//  simulator-trainer
//
//  Created by m1book on 6/3/25.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CycriptLauncher : NSObject

+ (BOOL)beginSessionForProcessNamed:(NSString *)processName;

@end

NS_ASSUME_NONNULL_END
