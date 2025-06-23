//
//  CycriptLauncher.m
//  simulator-trainer
//
//  Created by m1book on 6/3/25.
//

#import <libproc.h>
#import "TerminalWindowController.h"
#import "CycriptLauncher.h"
#import "AppBinaryPatcher.h"
#import "CommandRunner.h"

@implementation CycriptLaunchRequest
@end

@interface CycriptLauncher ()
- (NSString *)_cycriptExecutablePath;
- (pid_t)_getProcessIDForTarget:(NSString *)target;
@end

@implementation CycriptLauncher

- (id)initWithRequest:(CycriptLaunchRequest *)request {
    if ((self = [super init])) {
        _request = request;
    }
    
    return self;
}

- (NSString *)_cycriptExecutablePath {
    NSString *cycriptAssetPath = [[NSBundle bundleForClass:[self class]] pathForResource:@"cycript_mac" ofType:nil];
    NSString *cycriptCliPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"cycript"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:cycriptCliPath]) {
        [[NSFileManager defaultManager] removeItemAtPath:cycriptCliPath error:nil];
    }

    [[NSFileManager defaultManager] copyItemAtPath:cycriptAssetPath toPath:cycriptCliPath error:nil];
    return  cycriptCliPath;
}

- (pid_t)_getProcessIDForTarget:(NSString *)target {
    int pids[1024];
    int count = proc_listpids(PROC_ALL_PIDS, 0, pids, sizeof(pids));
    if (count <= 0) {
        NSLog(@"Failed to list processes");
        return -1;
    }
    
    for (int i = 0; i < count; i++) {
        if (pids[i] == 0) {
            continue;
        }

        char namebuf[PROC_PIDPATHINFO_MAXSIZE];
        proc_pidpath(pids[i], namebuf, sizeof(namebuf));
        
        NSString *processName = [NSString stringWithUTF8String:namebuf];
        if ([processName containsString:target]) {
            return pids[i];
        }
    }
    
    return -1;
}

- (pid_t)_launchTargetProcess {
    if (self.request.processName && self.request.processName.length > 0) {
        return [self _getProcessIDForTarget:self.request.processName];
    }
    else if (self.request.targetBundleId && self.request.targetBundleId.length > 0) {
        
        NSString *libInAssetPath = [[NSBundle bundleForClass:[self class]] pathForResource:@"cycript_server.dylib" ofType:nil];
        NSString *libInTmpPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"cycript_server.dylib"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:libInTmpPath]) {
            NSError *error = nil;
            [[NSFileManager defaultManager] removeItemAtPath:libInTmpPath error:&error];
            if (error) {
                NSLog(@"Failed to remove old library file: %@", error);
                return NO;
            }
        }
        [[NSFileManager defaultManager] copyItemAtPath:libInAssetPath toPath:libInTmpPath error:nil];
        
        __block pid_t pid = -1;
//        dispatch_semaphore_t sema = dispatch_semaphore_create(0);
//        [AppBinaryPatcher codesignItemAtPath:libInTmpPath completion:^(BOOL success, NSError * _Nullable error) {
//            if (error) {
//                NSLog(@"Failed to codesign libobjsee: %@", error);
//                return;
//            }
//
        int cycript_server_port = (9973 * getpid()) % 49901 + 8100;
        self.request.serverPort = cycript_server_port;
            NSArray *xcrunArgs = @[@"simctl", @"launch", @"--terminate-running-process", self.request.targetDeviceId, self.request.targetBundleId];
            NSDictionary *envs = @{
                @"SIMCTL_CHILD_DYLD_INSERT_LIBRARIES": libInTmpPath,
                @"SIMCTL_CHILD_CYCRIPT_SERVER_PORT": [NSString stringWithFormat:@"%d", cycript_server_port],
            };
            
            NSString *output = nil;
            [CommandRunner runCommand:@"/usr/bin/xcrun" withArguments:xcrunArgs cwd:nil environment:envs stdoutString:&output error:nil];
            
            NSString *pidString = [output componentsSeparatedByString:@":"].lastObject;
            pid = (pid_t)[pidString integerValue];
//            dispatch_semaphore_signal(sema);
//        }];
        
//        dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)));
        return pid;
    }
    else {
        return -1;
    }
}

- (int)_readServerPortFromSockForPid:(pid_t)pid {
    char socket_path[64];
    snprintf(socket_path, sizeof(socket_path), "/var/tmp/cycript-port.%d.sock", pid);
    int sock = socket(AF_UNIX, SOCK_STREAM, 0);
    if (sock < 0) {
        NSLog(@"Failed to create socket: %s", strerror(errno));
        return NO;
    }
    
    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, socket_path, sizeof(addr.sun_path) - 1);
    
    for (int i = 0; i < 50; i++) {
        if (connect(sock, (struct sockaddr *)&addr, sizeof(addr)) == 0) {
            break;
        }
        
        usleep(100000);
    }
    
    int cycript_server_port = -1;
    ssize_t n = recv(sock, &cycript_server_port, sizeof(cycript_server_port), 0);
    close(sock);
    
    if (n != sizeof(cycript_server_port) || cycript_server_port <= 0) {
        NSLog(@"Failed to receive cycript port");
        return NO;
    }
    
    return cycript_server_port;
}

- (BOOL)launch {

    if (!self.request.serverPort || self.request.serverPort <= 0) {
        pid_t pid = [self _launchTargetProcess];
        if (pid <= 0) {
            NSLog(@"Failed to find running process for request %@", self.request);
            return NO;
        }
    }

    int cycript_server_port = (int)self.request.serverPort;
    if (cycript_server_port <= 0) {
        NSLog(@"Invalid or missing cycript server port");
        return NO;
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSString *termTitle = [NSString stringWithFormat:@"cycript -- (127.0.0.1:%d)", cycript_server_port];
        NSArray *cycriptArgs = @[@"-r", [NSString stringWithFormat:@"127.0.0.1:%d", cycript_server_port]];
        [TerminalWindowController presentTerminalWithExecutable:[self _cycriptExecutablePath] args:cycriptArgs env:nil title:termTitle];
    });

    return YES;
}

@end
