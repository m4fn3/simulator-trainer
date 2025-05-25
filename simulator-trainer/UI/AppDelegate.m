//
//  AppDelegate.m
//  simulator-trainer
//
//  Created by Ethan Arbuckle on 4/28/25.
//

#import <Cocoa/Cocoa.h>
#import "AppDelegate.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import "CommandRunner.h"

@interface AppDelegate ()
@property (nonatomic, strong) id simulatorDelegate;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    [self setupSimulator];
}

- (void)setupSimulator {
    
    NSString *xcodeDeveloperPath = nil;
    [CommandRunner runCommand:@"/usr/bin/xcode-select" withArguments:@[@"--print-path"] stdoutString:&xcodeDeveloperPath error:nil];
    if (!xcodeDeveloperPath || ![xcodeDeveloperPath hasSuffix:@"/Contents/Developer"]) {
        NSLog(@"Xcode Developer path is not set correctly.");
        return;
    }
    
    NSString *simulatorPath = [xcodeDeveloperPath stringByAppendingPathComponent:@"Applications/Simulator.app"];
    NSString *simulatorExecutablePath = [simulatorPath stringByAppendingPathComponent:@"Contents/MacOS/Simulator"];
    
    Method mainBundleMethod = class_getClassMethod([NSBundle class], @selector(mainBundle));
    IMP originalMainBundleIMP = method_getImplementation(mainBundleMethod);
    IMP swizzledMainBundleIMP = imp_implementationWithBlock(^(id _self) {
        NSBundle *simulatorBundle = [NSBundle bundleWithPath:simulatorPath];
        if (simulatorBundle) {
            return simulatorBundle;
        }

        return ((NSBundle *(*)(id, SEL))originalMainBundleIMP)(_self, @selector(mainBundle));
    });
    
    method_setImplementation(mainBundleMethod, swizzledMainBundleIMP);
    
    Method boolForKeyMethod = class_getInstanceMethod([NSUserDefaults class], @selector(boolForKey:));
    IMP originalBoolForKeyIMP = method_getImplementation(boolForKeyMethod);
    IMP swizzledBoolForKeyIMP = imp_implementationWithBlock(^(id _self, NSString *key) {
    
        if ([@[@"CarPlayExtraOptions", @"DebugLogging", @"ShowFPS"] containsObject:key]) {
            return YES;
        }
        
        BOOL result = ((BOOL (*)(id, SEL, NSString *))originalBoolForKeyIMP)(_self, @selector(boolForKey:), key);
        return result;
    });
    method_setImplementation(boolForKeyMethod, swizzledBoolForKeyIMP);
    
    void *simhandle = dlopen("/Users/ethanarbuckle/Desktop/Simulator", 0);
    if (simhandle == NULL) {
        NSLog(@"Failed to load Simulator framework: %s", dlerror());
        return;
    }
    
    Class _SimulatorDeviceWindow = objc_getClass("_TtC9Simulator12DeviceWindow");
    SEL _performDragOperationSelector = sel_registerName("performDragOperation:");
    
    Method performDragOperationMethod = class_getInstanceMethod(_SimulatorDeviceWindow, _performDragOperationSelector);
    IMP originalPerformDragOperationIMP = method_getImplementation(performDragOperationMethod);
    IMP newPerformDragOperationIMP = imp_implementationWithBlock(^(id _self, id <NSDraggingInfo> sender) {
        
        NSPasteboard *pasteboard = [sender draggingPasteboard];
        NSString *draggedType = [[pasteboard types] firstObject];
        if (!draggedType || ![draggedType isEqualToString:NSPasteboardTypeFileURL]) {
            return NO;
        }
        
        NSArray *files = [pasteboard readObjectsForClasses:@[[NSURL class]] options:nil];
        if (files.count == 0 || ![files.firstObject isKindOfClass:[NSURL class]]) {
            return NO;
        }
        
        NSString *realPath = [[files firstObject] URLByResolvingSymlinksInPath].path;
        if ([[realPath pathExtension] isEqualToString:@"deb"]) {
            NSLog(@"Installing a tweak");
            return NO;
        }

        return ((BOOL (*)(id, SEL, id))originalPerformDragOperationIMP)(_self, _performDragOperationSelector, sender);
    });
    method_setImplementation(performDragOperationMethod, newPerformDragOperationIMP);
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        Class _SimulatorAppDelegate = objc_getClass("SimulatorAppDelegate");
        if (!_SimulatorAppDelegate) {
            NSLog(@"SimulatorAppDelegate class not found");
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
