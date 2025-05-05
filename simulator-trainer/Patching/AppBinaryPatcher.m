//
//  AppBinaryPatcher.m
//  simulator-trainer
//
//  Created by Ethan Arbuckle on 4/29/25.
//

#import "AppBinaryPatcher.h"

@implementation AppBinaryPatcher

- (void)injectDylib:(NSString *)dylibPath intoBinary:(NSString *)binaryPath completion:(void (^ _Nullable)(BOOL success, NSError * _Nullable error))completion {

    [self thinBinaryAtPath:binaryPath];

    NSString *optoolPath = [[NSBundle mainBundle] pathForResource:@"optool" ofType:nil];
    NSArray *arguments = @[
        @"install",
        @"LC_LOAD_DYLIB",
        @"-p", dylibPath,
        @"-t", binaryPath
    ];

    NSTask *optoolTask = [[NSTask alloc] init];
    optoolTask.launchPath = optoolPath;
    optoolTask.arguments = arguments;
    
    [optoolTask launch];
    [optoolTask waitUntilExit];
    
    if (optoolTask.terminationStatus != 0) {
        NSError *error = [NSError errorWithDomain:@"AppBinaryPatcher" code:1 userInfo:@{NSLocalizedDescriptionKey:@"optool failed"}];
        if (completion) {
            completion(NO, error);
        }
        return;
    }

    [self codesignItemAtPath:binaryPath completion:completion];
}

- (void)thinBinaryAtPath:(NSString *)binaryPath {
    NSTask *lipoTask = [[NSTask alloc] init];
    lipoTask.launchPath = @"/usr/bin/lipo";
    lipoTask.arguments = @[@"-info", binaryPath];

    NSPipe *pipe = [NSPipe pipe];
    lipoTask.standardOutput = pipe;
    lipoTask.standardError = pipe;

    [lipoTask launch];
    [lipoTask waitUntilExit];

    NSString *output = [[NSString alloc] initWithData:[[pipe fileHandleForReading] readDataToEndOfFile] encoding:NSUTF8StringEncoding];
    if ([output containsString:@"Non-fat"]) {
        return;
    }

    if ([output containsString:@"arm64"]) {
        NSString *tempPath = [binaryPath stringByAppendingString:@"_arm64"];
        NSTask *thinTask = [[NSTask alloc] init];
        thinTask.launchPath = @"/usr/bin/lipo";
        thinTask.arguments = @[@"-thin", @"arm64", binaryPath, @"-o", tempPath];
        [thinTask launch];
        [thinTask waitUntilExit];

        if ([[NSFileManager defaultManager] fileExistsAtPath:tempPath]) {
            [[NSFileManager defaultManager] removeItemAtPath:binaryPath error:nil];
            [[NSFileManager defaultManager] moveItemAtPath:tempPath toPath:binaryPath error:nil];
        }
    }
}

- (void)codesignItemAtPath:(NSString *)path completion:(void (^)(BOOL, NSError * _Nullable))completion {
    NSTask *codesignTask = [[NSTask alloc] init];
    codesignTask.launchPath = @"/usr/bin/codesign";
    codesignTask.arguments = @[@"-f", @"-s", @"-", @"--generate-entitlement-der", path];

    NSPipe *pipe = [NSPipe pipe];
    codesignTask.standardOutput = pipe;
    codesignTask.standardError = pipe;

    [codesignTask launch];
    [codesignTask waitUntilExit];

    NSString *output = [[NSString alloc] initWithData:[[pipe fileHandleForReading] readDataToEndOfFile] encoding:NSUTF8StringEncoding];
    if (codesignTask.terminationStatus == 0) {
        if (completion) {
            completion(YES, nil);
        }
    } else {
        NSError *error = [NSError errorWithDomain:@"AppBinaryPatcher" code:2 userInfo:@{NSLocalizedDescriptionKey: output}];
        if (completion) {
            completion(NO, error);
        }
    }
}

@end
