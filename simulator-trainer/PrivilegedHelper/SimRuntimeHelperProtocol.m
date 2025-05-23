//
//  SimRuntimeHelperProtocol.m
//  simulator-trainer
//
//  Created by Ethan Arbuckle on 5/17/25.
//

#import "SimRuntimeHelperProtocol.h"

NSString * const kSimRuntimeHelperServiceName = @"com.objc.simulator-trainer.SimRuntimeHelper";
NSString * const kSimRuntimeHelperAuthRightName = @"com.objc.simulator-trainer.helper.right";
NSString * const kSimRuntimeHelperAuthRightDefaultRule = @kAuthorizationRuleIsAdmin;
NSString * const kSimRuntimeHelperAuthRightDescription = @"Authorize simulator-trainer to modify simulator runtime overlays and jailbreak them.";
