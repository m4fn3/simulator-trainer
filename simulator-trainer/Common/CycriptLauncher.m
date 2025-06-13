//
//  CycriptLauncher.m
//  simulator-trainer
//
//  Created by m1book on 6/3/25.
//

#import <libproc.h>
#import "TerminalWindowController.h"
#import "CycriptLauncher.h"

@interface CycriptLauncher ()
+ (NSString *)_cycriptExecutablePath;
+ (pid_t)_getProcessIDForTarget:(NSString *)target;
@end

@implementation CycriptLauncher

+ (NSString *)_cycriptExecutablePath {
    NSString *cycriptAssetPath = [[NSBundle bundleForClass:[self class]] pathForResource:@"cycript_mac" ofType:nil];
    NSString *cycriptCliPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"cycript"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:cycriptCliPath]) {
        [[NSFileManager defaultManager] removeItemAtPath:cycriptCliPath error:nil];
    }

    [[NSFileManager defaultManager] copyItemAtPath:cycriptAssetPath toPath:cycriptCliPath error:nil];
    return  cycriptCliPath;
}

+ (pid_t)_getProcessIDForTarget:(NSString *)target {
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

+ (BOOL)beginSessionForProcessNamed:(NSString *)processName {
    pid_t pid = [CycriptLauncher _getProcessIDForTarget:processName];
    if (pid <= 0) {
        NSLog(@"Failed to find SpringBoard process");
        return NO;
    }

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
    
    NSString *cycriptPath = [CycriptLauncher _cycriptExecutablePath];
    if (!cycriptPath) {
        return NO;
    }

    NSString *termTitle = [NSString stringWithFormat:@"cycript -- SpringBoard (127.0.0.1:%d)", cycript_server_port];;
    [TerminalWindowController presentTerminalWithExecutable:cycriptPath args:@[@"-r", [NSString stringWithFormat:@"127.0.0.1:%d", cycript_server_port]] env:nil title:termTitle];

    return YES;
}

@end
