//
//  PackageInstallationService.m
//  simulator-trainer
//
//  Created by m1book on 5/23/25.
//

#import "PackageInstallationService.h"
#import "platform_changer.h"
#import "AppBinaryPatcher.h"
#import "CommandRunner.h"

@implementation PackageInstallationService

- (void)installDebFileAtPath:(NSString *)debPath toDevice:(BootedSimulatorWrapper *)device completion:(void (^)(NSError * _Nullable error))completion {
    if (!debPath || !device) {
        if (completion) {
            completion([NSError errorWithDomain:NSCocoaErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey: @"Invalid parameters: debPath or device is nil."}]);
        }
        
        return;
    }
        
    NSString *simRuntimeRoot = device.runtimeRoot;
    if (!simRuntimeRoot) {
        completion([NSError errorWithDomain:NSCocoaErrorDomain code:98 userInfo:@{NSLocalizedDescriptionKey: @"Simulator runtime root path is nil."}]);
        return;
    }
    
    NSString *tempExtractDir = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    NSString *dataTarExtractDir = [tempExtractDir stringByAppendingPathComponent:@"data_payload"];
    NSError * __block operationError = nil;
    
    if (![[NSFileManager defaultManager] createDirectoryAtPath:tempExtractDir withIntermediateDirectories:YES attributes:nil error:&operationError]) {
        if (completion) {
            completion(operationError);
        }
        
        return;
    }
    
    void (^cleanupBlock)(void) = ^{
        [[NSFileManager defaultManager] removeItemAtPath:tempExtractDir error:nil];
    };
    
    NSString *debFileName = [debPath lastPathComponent];
    NSString *copiedDebPath = [tempExtractDir stringByAppendingPathComponent:debFileName];
    if (![[NSFileManager defaultManager] copyItemAtPath:debPath toPath:copiedDebPath error:&operationError]) {
        cleanupBlock();
        if (completion) {
            completion(operationError);
        }

        return;
    }
    
    if (![CommandRunner runCommand:@"/usr/bin/ar" withArguments:@[@"-x", copiedDebPath] cwd:tempExtractDir stdoutString:nil error:&operationError]) {
        cleanupBlock();
        if (completion) {
            completion(operationError);
        }
        
        return;
    }

    NSString *dataTarName = nil;
    NSArray *possibleDataTarNames = @[@"data.tar.gz", @"data.tar.xz", @"data.tar.zst", @"data.tar.bz2", @"data.tar,", @"data.tar.lzma"];
    for (NSString *name in possibleDataTarNames) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:[tempExtractDir stringByAppendingPathComponent:name]]) {
            dataTarName = name;
            break;
        }
    }
    
    if (!dataTarName) {
        cleanupBlock();
        if (completion) {
            completion([NSError errorWithDomain:NSCocoaErrorDomain code:101 userInfo:@{NSLocalizedDescriptionKey: @"No data.tar found in the deb package"}]);
        }
        
        return;
    }
    
    NSString *dataTarPath = [tempExtractDir stringByAppendingPathComponent:dataTarName];
    if (![[NSFileManager defaultManager] createDirectoryAtPath:dataTarExtractDir withIntermediateDirectories:YES attributes:nil error:&operationError]) {
        cleanupBlock();
        if (completion) {
            completion(operationError);
        }
        
        return;
    }
    
    if (![CommandRunner runCommand:@"/usr/bin/tar" withArguments:@[@"-xf", dataTarPath, @"-C", dataTarExtractDir] stdoutString:nil error:&operationError]) {
        cleanupBlock();
        if (completion) {
            completion(operationError);
        }
        return;
    }
    
    NSDirectoryEnumerator *dirEnumerator = [[NSFileManager defaultManager] enumeratorAtPath:dataTarExtractDir];
    NSString *fileRelativeInDataTar;
    while ((fileRelativeInDataTar = [dirEnumerator nextObject])) {
        NSString *sourcePath = [dataTarExtractDir stringByAppendingPathComponent:fileRelativeInDataTar];
        
        BOOL isDir;
        if ([[NSFileManager defaultManager] fileExistsAtPath:sourcePath isDirectory:&isDir] && !isDir) {
            NSString *cleanedRelativePath = [fileRelativeInDataTar copy];
            if ([cleanedRelativePath hasPrefix:@"./"]) {
                cleanedRelativePath = [cleanedRelativePath substringFromIndex:2];
            }
            
            NSString *destinationPath = [simRuntimeRoot stringByAppendingPathComponent:cleanedRelativePath];
            NSString *destinationParentDir = [destinationPath stringByDeletingLastPathComponent];
            
            if (![[NSFileManager defaultManager] fileExistsAtPath:destinationParentDir]) {
                if (![[NSFileManager defaultManager] createDirectoryAtPath:destinationParentDir withIntermediateDirectories:YES attributes:nil error:&operationError]) {
                    cleanupBlock();
                    if (completion) {
                        completion(operationError);
                    }
                    
                    return;
                }
            }
            
            if ([[NSFileManager defaultManager] fileExistsAtPath:destinationPath]) {
                [[NSFileManager defaultManager] removeItemAtPath:destinationPath error:NULL];
            }
            
            if (![[NSFileManager defaultManager] copyItemAtPath:sourcePath toPath:destinationPath error:&operationError]) {
                NSLog(@"  copy error: %@", operationError);
                cleanupBlock();
                if (completion) {
                    completion(operationError);
                }
                return;
            }
            
            if ([destinationPath.pathExtension isEqualToString:@"dylib"] && ![AppBinaryPatcher isBinaryArm64SimulatorCompatible:destinationPath]) {
                // Convert to simulator platform and then codesign
                [AppBinaryPatcher thinBinaryAtPath:destinationPath];
                convertPlatformToSimulator(destinationPath.UTF8String);
                
                [AppBinaryPatcher codesignItemAtPath:destinationPath completion:^(BOOL success, NSError *error) {
                    if (!success) {
                        NSLog(@"Failed to codesign item at path: %@", error);
                    }
                }];
            }
        }
    }

    cleanupBlock();

    [device respring];

    if (completion) {
        completion(nil);
    }
}

@end
