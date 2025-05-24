//
//  main.m
//  SimRuntimeHelper
//
//  Created by Ethan Arbuckle on 5/17/25.
//

#import <Foundation/Foundation.h>
#import "SimRuntimeHelperProtocol.h"
#import "AppBinaryPatcher.h"
#import "tmpfs_overlay.h"

@interface SimRuntimeHelper : NSObject <NSXPCListenerDelegate, SimRuntimeHelperProtocol>
@property (atomic, strong) NSXPCListener *listener;
- (void)startListener;
@end

@implementation SimRuntimeHelper

- (id)init {
    if ((self = [super init])) {
        self.listener = [[NSXPCListener alloc] initWithMachServiceName:kSimRuntimeHelperServiceName];
        self.listener.delegate = self;
    }
    
    return self;
}

- (void)startListener {
    [self.listener resume];
    [[NSRunLoop currentRunLoop] run];
}

- (BOOL)listener:(NSXPCListener *)listener shouldAcceptNewConnection:(NSXPCConnection *)newConnection {
    newConnection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SimRuntimeHelperProtocol)];
    newConnection.exportedObject = self;
    [newConnection resume];
    return YES;
}

- (void)setupTweakInjectionWithOptions:(SimInjectionOptions *)options completion:(void (^)(NSError *error))completion {
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
                [[NSFileManager defaultManager] createDirectoryAtPath:targetDir withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@(0777)} error:&error];
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

- (void)mountTmpfsOverlaysAtPaths:(NSArray<NSString *> *)overlayPaths completion:(void (^)(NSError *error))completion {
    for (NSString *overlayPath in overlayPaths) {
        NSError *error = nil;
        if (![self _mountOverlayAtPath:overlayPath error:&error]) {
            NSLog(@"Failed to mount overlay at path: %@ with error: %@", overlayPath, error);
            completion(error);
            return;
        }
        
        // Set permissions to allow the non-privileged app to read+write to the overlay
        [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions: @(0777)} ofItemAtPath:overlayPath error:&error];
        if (error) {
            NSLog(@"Failed to set permissions for overlay at path: %@ with error: %@", overlayPath, error);
            completion(error);
            return;
        }
    }
    
    completion(nil);
}

- (BOOL)_mountOverlayAtPath:(NSString *)overlayPath error:(NSError **)error {
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

- (void)unmountMountPoints:(NSArray <NSString *> *)mountPoints completion:(void (^)(NSError *))completion {
    for (NSString *mountPoint in mountPoints) {
        NSError *error = nil;
        if (![self _unmountOverlayAtPath:mountPoint error:&error]) {
            completion(error);
            return;
        }
    }
    
    completion(nil);
}

- (BOOL)_unmountOverlayAtPath:(NSString *)overlayPath error:(NSError **)error {
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


int main(int argc, const char * argv[]) {
    @autoreleasepool {
        SimRuntimeHelper *helper = [[SimRuntimeHelper alloc] init];
        [helper startListener];
    }

    return 0;
}
