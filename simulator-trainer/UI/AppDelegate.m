//
//  AppDelegate.m
//  simulator-trainer
//
//  Created by Ethan Arbuckle on 4/28/25.
//

#import "AppDelegate.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>

@interface AppDelegate ()
@property (nonatomic, strong) id simulatorDelegate;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    [self setupSimulator];
}

- (void)setupSimulator {
    Method mainBundleMethod = class_getClassMethod([NSBundle class], @selector(mainBundle));
    IMP originalMainBundleIMP = method_getImplementation(mainBundleMethod);
    IMP swizzledMainBundleIMP = imp_implementationWithBlock(^(id _self) {
        
        NSBundle *simulatorBundle = [NSBundle bundleWithPath:@"/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app/"];
        if (simulatorBundle) {
            return simulatorBundle;
        }

        return ((NSBundle *(*)(id, SEL))originalMainBundleIMP)(_self, @selector(mainBundle));
    });
    
    method_setImplementation(mainBundleMethod, swizzledMainBundleIMP);
    
    Method boolForKeyMethod = class_getInstanceMethod([NSUserDefaults class], @selector(boolForKey:));
    IMP originalBoolForKeyIMP = method_getImplementation(boolForKeyMethod);
    IMP swizzledBoolForKeyIMP = imp_implementationWithBlock(^(id _self, NSString *key) {
        if ([key isEqualToString:@"UseMonobar"]) {
            return NO;
        }
        
        if ([@[@"CarPlayExtraOptions", @"ShowTestingDevices", @"DebugLogging", @"ShowUITestMenu", @"ShowFPS"] containsObject:key]) {
            return YES;
        }
        
        BOOL result = ((BOOL (*)(id, SEL, NSString *))originalBoolForKeyIMP)(_self, @selector(boolForKey:), key);
        NSLog(@"boolForKey: %@ -> %d", key, result);
        return result;
    });
    method_setImplementation(boolForKeyMethod, swizzledBoolForKeyIMP);
    
    Method stringForKeyMethod = class_getInstanceMethod([NSUserDefaults class], @selector(stringForKey:));
    IMP originalStringForKeyIMP = method_getImplementation(stringForKeyMethod);
    IMP swizzledStringForKeyIMP = imp_implementationWithBlock(^(id _self, NSString *key) {
        NSString *result = ((NSString *(*)(id, SEL, NSString *))originalStringForKeyIMP)(_self, @selector(stringForKey:), key);
        NSLog(@"stringForKey: %@ -> %@", key, result);
        return result;
    });
    method_setImplementation(stringForKeyMethod, swizzledStringForKeyIMP);
    
    void *simhandle = dlopen("/Users/ethanarbuckle/Desktop/Simulator", 0);
    if (simhandle == NULL) {
        NSLog(@"Failed to load Simulator framework: %s", dlerror());
        return;
    }
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        Class _SimulatorAppDelegate = objc_getClass("SimulatorAppDelegate");
        if (!_SimulatorAppDelegate) {
            NSLog(@"SimulatorAppDelegate class not found.");
            return;
        }
        
        self.simulatorDelegate = [[_SimulatorAppDelegate alloc] init];
        ((void (*)(id, SEL, id))objc_msgSend)(self.simulatorDelegate, sel_registerName("applicationDidFinishLaunching:"), nil);
        
        NSBundle *simBundle = [NSBundle bundleWithPath:@"/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app"];
        NSArray *topObjects = nil;
        [simBundle loadNibNamed:@"MainMenu" owner:NSApp topLevelObjects:&topObjects];
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            id appleInternalMenuItem = ((id (*)(id, SEL))objc_msgSend)(self.simulatorDelegate, sel_registerName("dockMenu"));
            NSLog(@"Apple Internal Menu Item: %@", appleInternalMenuItem);
        });
    });
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
}


- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app {
    return YES;
}

- (id)forwardingTargetForSelector:(SEL)aSelector {
    if ([self.simulatorDelegate respondsToSelector:aSelector]) {
        return self.simulatorDelegate;
    }

    return [super forwardingTargetForSelector:aSelector];
}

@end
