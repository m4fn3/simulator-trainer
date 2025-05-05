//
//  CommandRunner.m
//  interjector-macos
//
//  Created by Ethan Arbuckle on 3/15/24.
//

#import "CommandRunner.h"

@implementation CommandRunner

+ (BOOL)runCommand:(NSString *)command withArguments:(NSArray<NSString *> *)arguments stdoutString:(NSString * _Nullable *)stdoutString error:(NSError ** _Nullable)errorOut {

    NSTask *task = [[NSTask alloc] init];
    task.launchPath = command;
    task.arguments = arguments;
    
    NSPipe *outputPipe = nil;
    if (stdoutString != nil) {
        outputPipe = [NSPipe pipe];
        [task setStandardOutput:outputPipe];
    }
    
    NSPipe *errorPipe = [NSPipe pipe];
    [task setStandardError:errorPipe];

    [task launch];
    [task waitUntilExit];
    
    if (task.terminationStatus != 0 && errorOut) {

        NSString *stdErrString = [CommandRunner _readStringFromPipe:errorPipe withTimeout:5];
        if (stdErrString) {
            NSDictionary *userInfo = @{NSLocalizedDescriptionKey: stdErrString};
            *errorOut = [NSError errorWithDomain:@"ExecutionError" code:task.terminationStatus userInfo:userInfo];
        }
        else {
            *errorOut = [NSError errorWithDomain:@"ExecutionError" code:task.terminationStatus userInfo:nil];
        }
    }
    
    // Read stdout if caller requested it
    if (stdoutString != nil) {
        *stdoutString = [CommandRunner _readStringFromPipe:outputPipe withTimeout:5];
    }
    
    // Close stdio pipes
    if (outputPipe) {
        [[outputPipe fileHandleForReading] closeFile];
    }
    [[errorPipe fileHandleForReading] closeFile];
    
    return task.terminationStatus == 0;
}

+ (NSString *)_readStringFromPipe:(NSPipe *)pipe withTimeout:(NSTimeInterval)timeout {
    
    dispatch_queue_t readQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    
    __block NSData *readData = nil;
    dispatch_async(readQueue, ^{
        readData = [pipe.fileHandleForReading availableData];
        dispatch_semaphore_signal(sem);
    });
    
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC)));
    if (readData.length > 0) {
        
        NSString *output = [[NSString alloc] initWithData:readData encoding:NSUTF8StringEncoding];
        
        // Strip trailing newline
        if ([output hasSuffix:@"\n"]) {
            output = [output substringToIndex:(output.length - 1)];
        }
        
        return output;
    }
    
    return nil;
}
                   
@end
