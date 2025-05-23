//
//  SimHelperCommon.m
//  simulator-trainer
//
//  Created by Ethan Arbuckle on 5/17/25.
//

#import "SimHelperCommon.h"
#import "AppBinaryPatcher.h"
#import "CommandRunner.h"
#import "tmpfs_overlay.h"

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

+ (void)installTweakLoaderWithOptions:(SimInjectionOptions *)options completion:(void (^)(NSError *error))completion {
    if (!options || !options.tweakLoaderSourcePath || !options.tweakLoaderDestinationPath || !options.victimPathForTweakLoader) {
        if (completion) {
            NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:paramErr userInfo:@{NSLocalizedDescriptionKey: @"Invalid options"}];
            completion(error);
        }
        return;
    }
    
    __block NSError *error = nil;
    if (![[NSFileManager defaultManager] fileExistsAtPath:options.tweakLoaderDestinationPath]) {
        [[NSFileManager defaultManager] copyItemAtPath:options.tweakLoaderSourcePath toPath:options.tweakLoaderDestinationPath error:&error];
    
        for (NSString *sourcePath in options.filesToCopy) {
            NSString *targetPath = options.filesToCopy[sourcePath];
            if ([[NSFileManager defaultManager] fileExistsAtPath:targetPath]) {
                NSLog(@"File already exists at target path: %@", targetPath);
                continue;
            }
    
            NSString *targetDir = [targetPath stringByDeletingLastPathComponent];
            if (![[NSFileManager defaultManager] fileExistsAtPath:targetDir]) {
                NSError *error = nil;
                [[NSFileManager defaultManager] createDirectoryAtPath:targetDir withIntermediateDirectories:YES attributes:nil error:&error];
                if (error) {
                    NSLog(@"Failed to create target directory: %@", error);
                    break;
                }
            }
    
            [[NSFileManager defaultManager] copyItemAtPath:sourcePath toPath:targetPath error:&error];
            if (error) {
                NSLog(@"Failed to copy file from %@ to %@: %@", sourcePath, targetPath, error);
                break;
            }
        }
        
        if (!error) {
            [AppBinaryPatcher injectDylib:options.tweakLoaderDestinationPath intoBinary:options.victimPathForTweakLoader usingOptoolAtPath:options.optoolPath completion:^(BOOL success, NSError *patchError) {
                error = patchError;
            }];
        }
        else {
            NSLog(@"Failed to copy loader: %@", error);
            error = [NSError errorWithDomain:NSOSStatusErrorDomain code:errAuthorizationDenied userInfo:@{NSLocalizedDescriptionKey: @"Failed to copy tweakloader into simruntime"}];
        }
    }
    
    
    
    if (completion) {
        completion(error);
    }
}

+ (BOOL)mountOverlayAtPath:(NSString *)overlayPath error:(NSError **)error {
    if (!overlayPath) {
        if (error) {
            *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:paramErr userInfo:@{NSLocalizedDescriptionKey: @"Invalid overlay path"}];
        }
        
        return NO;
    }
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:overlayPath]) {
        NSError *createError = nil;
        [[NSFileManager defaultManager] createDirectoryAtPath:overlayPath withIntermediateDirectories:YES attributes:nil error:&createError];
        if (createError && error) {
            *error = createError;
        }
        
        return NO;
    }
    
    if (create_or_remount_overlay_symlinks(overlayPath.UTF8String) != 0) {
        if (error) {
            *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:errAuthorizationDenied userInfo:@{NSLocalizedDescriptionKey: @"Failed to mount overlay"}];
        }
        
        return NO;
    }
    
    return YES;
}

+ (BOOL)unmountOverlayAtPath:(NSString *)overlayPath error:(NSError **)error {
    if (!overlayPath) {
        if (error) {
            *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:paramErr userInfo:@{NSLocalizedDescriptionKey: @"Invalid overlay path"}];
        }
        
        return NO;
    }
    
    if (unmount_if_mounted(overlayPath.UTF8String) != 0) {
        if (error) {
            *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:errAuthorizationDenied userInfo:@{NSLocalizedDescriptionKey: @"Failed to unmount overlay"}];
        }
        
        return NO;
    }
    
    return YES;
}

@end
