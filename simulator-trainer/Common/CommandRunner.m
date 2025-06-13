//
//  CommandRunner.m
//
//
//  Created by Ethan Arbuckle on 3/15/24.
//

#import "CommandRunner.h"

@implementation CommandRunner

+ (BOOL)runCommand:(NSString *)command withArguments:(NSArray<NSString *> *)arguments stdoutString:(NSString * _Nullable * _Nullable)stdoutString error:(NSError ** _Nullable)error {
    return [self runCommand:command withArguments:arguments cwd:nil environment:nil stdoutString:stdoutString error:error];
}

+ (BOOL)runCommand:(NSString *)command withArguments:(NSArray<NSString *> *)arguments cwd:(NSString * _Nullable)cwdPath environment:(NSDictionary * _Nullable)environment stdoutString:(NSString * _Nullable *)stdoutString error:(NSError ** _Nullable)errorOut {
    if (!command) {
        NSLog(@"No command provided to runCommand. Command %@, Arguments %@", command, arguments);
        if (errorOut) {
            *errorOut = [NSError errorWithDomain:NSCocoaErrorDomain code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Command is nil"}];
        }

        return NO;
    }
    
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = command;
    task.arguments = arguments;
    
    NSPipe *outputPipe = nil;
    if (stdoutString != nil) {
        outputPipe = [NSPipe pipe];
        task.standardOutput = outputPipe;
    }
    
    NSPipe *errorPipe = [NSPipe pipe];
    task.standardError = errorPipe;
    
    NSDictionary *env = [[NSProcessInfo processInfo] environment];
    if (environment) {
        NSMutableDictionary *mutableEnv = [NSMutableDictionary dictionaryWithDictionary:env];
        [mutableEnv addEntriesFromDictionary:environment];
        env = mutableEnv;
    }
    task.environment = env;
    
    if (cwdPath) {
        task.currentDirectoryPath = cwdPath;
    }

    [task launch];
    [task waitUntilExit];
    
    NSString *stdErrString = [CommandRunner _readStringFromPipe:errorPipe withTimeout:5.0];
    NSString *commandOutput = nil;
    if (outputPipe != nil) {
        commandOutput = [CommandRunner _readStringFromPipe:outputPipe withTimeout:5.0];
        if (stdoutString != nil) {
            *stdoutString = commandOutput;
        }
    }

    [[errorPipe fileHandleForReading] closeFile];
    if (outputPipe) {
        [[outputPipe fileHandleForReading] closeFile];
    }
    
    if (task.terminationStatus != 0 && errorOut) {
        *errorOut = [NSError errorWithDomain:@"CommandExecutionErrorDomain" code:task.terminationStatus userInfo:@{
            NSLocalizedDescriptionKey: @"Command execution failed",
            NSUnderlyingErrorKey: [NSError errorWithDomain:@"CommandExecutionErrorDomain" code:task.terminationStatus userInfo:@{
                NSLocalizedDescriptionKey: @"Command execution failed",
                @"CommandPath": command,
                @"Arguments": arguments ?: @[],
                @"TerminationStatus": @(task.terminationStatus),
                @"CommandOutput": commandOutput ?: @"",
                @"CommandError": stdErrString ?: @""
            }],
        }];
    }

    return task.terminationStatus == 0;
}

+ (NSString * _Nullable)_readStringFromPipe:(NSPipe *)pipe withTimeout:(NSTimeInterval)timeout {
    __block NSData *readData = nil;

    if (timeout <= 0) {
        readData = [pipe.fileHandleForReading readDataToEndOfFile];
    }
    else {
        dispatch_queue_t read_queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);

        dispatch_semaphore_t sem = dispatch_semaphore_create(0);
        dispatch_async(read_queue, ^{
            readData = [pipe.fileHandleForReading readDataToEndOfFile];
            dispatch_semaphore_signal(sem);
        });

        if (dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC))) != 0) {
            NSLog(@"Timeout reading from pipe after %f seconds.", timeout);
            return nil;
        }
    }

    if (readData && readData.length > 0) {
        NSString *output = [[NSString alloc] initWithData:readData encoding:NSUTF8StringEncoding];
        if ([output hasSuffix:@"\n"]) {
            output = [output substringToIndex:(output.length - 1)];
        }

        return output;
    }

    return nil;
}

                   
@end
