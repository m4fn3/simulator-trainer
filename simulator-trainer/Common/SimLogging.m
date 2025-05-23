//
//  SimLogging.m
//  simulator-trainer
//
//  Created by m1book on 5/22/25.
//

#import "SimLogging.h"
#import <dlfcn.h>

// Filter out some of the spammy Simulator logs
const NSString *kSimLogIgnoreStrings[] = {
    @" is handling device added notification: ",
    @"-[SimDeviceSet addDeviceAsync:]:",
    @"On devices queue adding device",
    @" to _devicesByUDID for set ",
    @"VolumeManager: Appeared: Ignoring",
    @"Ignoring disk due to missing volume path.",
    @"Found duplicate SDKs for",
    @" New device pair (",
    @"Runtime bundle found. Adding to supported runtimes",
    @"VolumeManager: Disk Appeared <DADisk ",
};

static void _SimServiceLog(int level, const char *function, int line, NSString *format, va_list args) {
    if (!format) {
        return;
    }

    NSString *formattedString = [[NSString alloc] initWithFormat:format arguments:args];
    if (formattedString) {
        NSString *logString = [NSString stringWithFormat:@"%s:%d %@", function, line, formattedString];
        // Check if the log message contains any of the ignore strings.
        // This happens after building the message because some of the ignore-strings include function names
        for (int i = 0; i < sizeof(kSimLogIgnoreStrings) / sizeof(NSString *); i++) {
            if ([logString containsString:(NSString *)kSimLogIgnoreStrings[i]]) {
                return;
            }
        }
        
        NSLog(@"%@", logString);
    }
}

@implementation SimLogging

+ (void)observeSimulatorLogs {
    // Register a logging handler for the Simulator. This will receive all logs regardless of their level
    void *coreSimHandle = dlopen("/Library/Developer/PrivateFrameworks/CoreSimulator.framework/Versions/A/CoreSimulator", RTLD_GLOBAL);
    void *_SimLogSetHandler = dlsym(coreSimHandle, "SimLogSetHandler");
    if (_SimLogSetHandler == NULL) {
        NSLog(@"Failed to find SimLogSetHandler. CoreSimulator handle: %p", coreSimHandle);
        return;
    }
    
    ((void (*)(void *))_SimLogSetHandler)(_SimServiceLog);
}

@end
