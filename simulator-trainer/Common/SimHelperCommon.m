//
//  SimHelperCommon.m
//  simulator-trainer
//
//  Created by Ethan Arbuckle on 5/17/25.
//

#import "SimHelperCommon.h"

NSString * const kSimRuntimeHelperServiceName = @"com.objc.simulator-trainer.SimRuntimeHelper";
NSString * const kSimRuntimeHelperAuthRightName = @"com.objc.simulator-trainer.helper.right";
NSString * const kSimRuntimeHelperAuthRightDefaultRule = @kAuthorizationRuleIsAdmin;
NSString * const kSimRuntimeHelperAuthRightDescription = @"Authorize simulator-trainer to modify simulator runtime overlays and jailbreak them.";


@implementation SimHelperCommon

+ (void)grantAuthorizationRights:(AuthorizationRef)authRef {
    if (authRef == NULL) {
        return;
    }
    
    // See if the right already exists by asking for its definition. If it does exist, there's nothing to do
    if (AuthorizationRightGet(kSimRuntimeHelperAuthRightName.UTF8String, NULL) == errAuthorizationDenied) {
        // If the right doesn't exist, create it with the default rule
        CFTypeRef rule = (__bridge CFTypeRef)kSimRuntimeHelperAuthRightDefaultRule;
        CFStringRef description = (__bridge CFStringRef)kSimRuntimeHelperAuthRightDescription;
        
        if (AuthorizationRightSet(authRef, kSimRuntimeHelperAuthRightName.UTF8String, rule, description, NULL, NULL) != errAuthorizationSuccess) {
            // Failed to set the right. Auth failure
            NSLog(@"Failed to set authorization right");
        }
        else {
            NSLog(@"Successfully set authorization right");
        }
    }
}

@end
