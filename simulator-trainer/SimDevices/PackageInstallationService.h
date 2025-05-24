//
//  PackageInstallationService.h
//  simulator-trainer
//
//  Created by m1book on 5/23/25.
//

#import <Foundation/Foundation.h>
#import "BootedSimulatorWrapper.h"

NS_ASSUME_NONNULL_BEGIN

@interface PackageInstallationService : NSObject

- (void)installDebFileAtPath:(NSString *)debPath toDevice:(BootedSimulatorWrapper *)device completion:(void (^)(NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
