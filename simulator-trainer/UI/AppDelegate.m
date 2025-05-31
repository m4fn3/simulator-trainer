//
//  AppDelegate.m
//  simulator-trainer
//
//  Created by Ethan Arbuckle on 4/28/25.
//

#import "AppDelegate.h"
#import "InProcessSimulator.h"


@interface AppDelegate ()
@property (nonatomic, strong) InProcessSimulator *simInterposer;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    self.simInterposer = [InProcessSimulator setup];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
}

- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app {
    return YES;
}

- (id)forwardingTargetForSelector:(SEL)aSelector {
    if ([self.simInterposer.simulatorDelegate respondsToSelector:aSelector]) {
        return self.simInterposer.simulatorDelegate;
    }

    return [super forwardingTargetForSelector:aSelector];
}

@end
