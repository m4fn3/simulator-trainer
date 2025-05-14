//
//  AppBinaryPatcher.m
//  simulator-trainer
//
//  Created by Ethan Arbuckle on 4/29/25.
//

#import "AppBinaryPatcher.h"
#import "EAXCRun.h"
#import "CommandRunner.h"

@implementation AppBinaryPatcher

+ (void)injectDylib:(NSString *)dylibPath intoBinary:(NSString *)binaryPath completion:(void (^ _Nullable)(BOOL success, NSError * _Nullable error))completion {
    [AppBinaryPatcher thinBinaryAtPath:binaryPath];

    NSString *optoolPath = [[NSBundle mainBundle] pathForResource:@"optool" ofType:nil];
    NSArray *arguments = @[
        @"install",
        @"LC_LOAD_DYLIB",
        @"-p", dylibPath,
        @"-t", binaryPath
    ];

    NSString *optoolOutput = nil;
    NSError *optoolError = nil;
    if ([CommandRunner runCommand:optoolPath withArguments:arguments stdoutString:&optoolOutput error:&optoolError] == NO) {
        NSLog(@"optool error: %@", optoolError);
        if (completion) {
            completion(NO, optoolError);
        }
        
        return;
    }
    
    [AppBinaryPatcher codesignItemAtPath:binaryPath completion:completion];
}

+ (void)thinBinaryAtPath:(NSString *)binaryPath {
    NSString *output = [[EAXCRun sharedInstance] xcrunInvokeAndWait:@[@"lipo", @"-info", binaryPath]];
    if ([output containsString:@"arm64"]) {
        NSString *tempPath = [binaryPath stringByAppendingString:@"_arm64"];
       [[EAXCRun sharedInstance] xcrunInvokeAndWait:@[@"lipo", binaryPath, @"-thin", @"arm64", @"-o", tempPath]];
        
        if ([[NSFileManager defaultManager] fileExistsAtPath:tempPath]) {
            [[NSFileManager defaultManager] removeItemAtPath:binaryPath error:nil];
            [[NSFileManager defaultManager] moveItemAtPath:tempPath toPath:binaryPath error:nil];
        }
    }
}

+ (void)codesignItemAtPath:(NSString *)path completion:(void (^)(BOOL, NSError * _Nullable))completion {
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
    }
    else {
        NSError *error = [NSError errorWithDomain:@"AppBinaryPatcher" code:2 userInfo:@{NSLocalizedDescriptionKey: output}];
        if (completion) {
            completion(NO, error);
        }
    }
}

+ (BOOL)isBinaryArm64SimulatorCompatible:(NSString *)binaryPath {
    NSString *otoolOutput = [[EAXCRun sharedInstance] xcrunInvokeAndWait:@[@"otool", @"-l", binaryPath]];
    NSString *lipoOutput = [[EAXCRun sharedInstance] xcrunInvokeAndWait:@[@"lipo", @"-info", binaryPath]];
    return [lipoOutput containsString:@"arm64"] && [otoolOutput containsString:@"platform 7"];
}

//+ (BOOL)adhocSignBinary:(NSString *)binaryPath {
//    NSArray *arguments = @[@"codesign", @"-f", @"-s", @"-", binaryPath];
//    NSString *signOutput = [[EAXCRun sharedInstance] xcrunInvokeAndWait:arguments];
//    return signOutput && ![signOutput containsString:@"fail"];
//}

@end

