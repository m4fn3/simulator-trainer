//
//  SimInjectionOptions.h
//  simulator-trainer
//
//  Created by m1book on 5/18/25.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SimInjectionOptions : NSObject <NSSecureCoding>

@property (nonatomic, strong) NSString *tweakLoaderSourcePath;
@property (nonatomic, strong) NSString *tweakLoaderDestinationPath;
@property (nonatomic, strong) NSString *victimPathForTweakLoader;
@property (nonatomic, strong) NSString *optoolPath;
@property (nonatomic, strong) NSDictionary *filesToCopy;

@end

NS_ASSUME_NONNULL_END
