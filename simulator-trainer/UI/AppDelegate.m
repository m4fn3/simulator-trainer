//
//  AppDelegate.m
//  simulator-trainer
//
//  Created by Ethan Arbuckle on 4/28/25.
//

#import "AppDelegate.h"
#import "InProcessSimulator.h"

@interface AppDelegate ()
@property (nonatomic, strong) NSWindowController *mainWindowController;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(makeWindowVisible) name:@"SimForgeShowMainWindow" object:nil];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
}

- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app {
    return YES;
}

- (void)makeWindowVisible {
    if (self.mainWindowController == nil || self.mainWindowController.window == nil) {
        NSStoryboard *storyboard = [NSStoryboard storyboardWithName:@"Main" bundle:nil];
        self.mainWindowController = [storyboard instantiateControllerWithIdentifier:@"MainWindowController"];
    }

    [self.mainWindowController showWindow:self];

    [self.mainWindowController.window makeKeyAndOrderFront:self];
    [NSApp activateIgnoringOtherApps:YES];
}

- (id)forwardingTargetForSelector:(SEL)aSelector {
    id receiver = [InProcessSimulator sharedSetupIfNeeded].simulatorDelegate;
    if ([receiver respondsToSelector:aSelector]) {
        return receiver;
    }
    
    return [super forwardingTargetForSelector:aSelector];
}

@end
