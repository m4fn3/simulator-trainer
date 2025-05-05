//
//  AppBinaryPatcher.h
//  simulator-trainer
//
//  Created by Ethan Arbuckle on 4/29/25.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface AppBinaryPatcher : NSObject

- (void)injectDylib:(NSString *)dylibPath intoBinary:(NSString *)binaryPath completion:(void (^ _Nullable)(BOOL success, NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
