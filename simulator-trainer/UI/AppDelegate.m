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
#import "dylib_conversion.h"
#import "AppBinaryPatcher.h"

@interface AppDelegate ()
@property (nonatomic, strong) id simulatorDelegate;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    [self convertSimulatorToDylibWithCompletion:^(NSString *dylibPath) {
        if (dylibPath) {
            [self launchSimulatorFromDylib:dylibPath];
        } else {
            NSLog(@"Failed to convert Simulator.app to dylib");
        }
    }];
}

- (NSString *)simulatorBundlePath {
    static NSString *simulatorBundlePath = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *xcodeDeveloperPath = nil;
        [CommandRunner runCommand:@"/usr/bin/xcode-select" withArguments:@[@"--print-path"] stdoutString:&xcodeDeveloperPath error:nil];
        if (!xcodeDeveloperPath || ![xcodeDeveloperPath hasSuffix:@"/Contents/Developer"]) {
            NSLog(@"Failed to get Xcode Developer path -- cannot find Simulator.app");
        }
        else {
            simulatorBundlePath = [xcodeDeveloperPath stringByAppendingPathComponent:@"Applications/Simulator.app"];
        }
    });
    
    return simulatorBundlePath;
}

- (void)convertSimulatorToDylibWithCompletion:(void (^)(NSString *dylibPath))completion {
    // Make a copy of the Simulator.app executable at $TMPDIR/Simulator.dylib
    NSString *simulatorExecutablePath = [[self simulatorBundlePath] stringByAppendingPathComponent:@"Contents/MacOS/Simulator"];
    NSString *simulatorDylibPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"Simulator.dylib"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:simulatorExecutablePath]) {
        [[NSFileManager defaultManager] removeItemAtPath:simulatorDylibPath error:nil];
    }
    [[NSFileManager defaultManager] copyItemAtPath:simulatorExecutablePath toPath:simulatorDylibPath error:nil];

    // Convert the simulator executable into a dylib (in-place)
    [AppBinaryPatcher thinBinaryAtPath:simulatorDylibPath];
    if (!convert_to_dylib_inplace(simulatorDylibPath.UTF8String)) {
        NSLog(@"Failed to convert Simulator.app to dylib");
        [[NSFileManager defaultManager] removeItemAtPath:simulatorDylibPath error:nil];
        return;
    }
    
    // Then codesign the dylib
    [AppBinaryPatcher codesignItemAtPath:simulatorDylibPath completion:^(BOOL success, NSError * _Nullable error) {
        if (error) {
            NSLog(@"Failed to codesign Simulator dylib: %@", error);
            [[NSFileManager defaultManager] removeItemAtPath:simulatorDylibPath error:nil];
            return;
        }
        
        // Simulator requires @rpath/SimulatorKit.framework. @loader_path/ was added as an rpath during dylib conversion, which makes dyld
        // consider the dylib's parent directory as a framework search path. Create a symlink next to the dylib, pointing to the real SimulatorKit.framework
        
        // Find the real SimulatorKit.framework, relative to the Simulator.app bundle path
        NSArray *simulatorBundlePathComponents = [[self simulatorBundlePath] pathComponents];
        NSString *xcodeDeveloperDir = [[simulatorBundlePathComponents subarrayWithRange:NSMakeRange(0, simulatorBundlePathComponents.count - 2)] componentsJoinedByString:@"/"];
        NSString *simulatorKitFrameworkPath = [xcodeDeveloperDir stringByAppendingPathComponent:@"Library/PrivateFrameworks/SimulatorKit.framework"];
        if (![[NSFileManager defaultManager] fileExistsAtPath:simulatorKitFrameworkPath]) {
            NSLog(@"SimulatorKit.framework not found at expected path: %@", simulatorKitFrameworkPath);
            [[NSFileManager defaultManager] removeItemAtPath:simulatorDylibPath error:nil];
            return;
        }
        
        NSString *simulatorKitSymlinkPath = [[simulatorDylibPath stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"SimulatorKit.framework"];
        NSError *symlinkError = nil;
        if (![[NSFileManager defaultManager] fileExistsAtPath:simulatorKitSymlinkPath]) {
            [[NSFileManager defaultManager] createSymbolicLinkAtPath:simulatorKitSymlinkPath withDestinationPath:simulatorKitFrameworkPath error:&symlinkError];
        }
        
        if (completion) {
            completion(simulatorDylibPath);
        }
    }];
}

- (void)launchSimulatorFromDylib:(NSString *)simulatorDylibPath {
    void *simHandle = dlopen([simulatorDylibPath UTF8String], 0);
    if (simHandle == NULL) {
        NSLog(@"Failed to load Simulator dylib: %s", dlerror());
        return;
    }
    
    Class _SimulatorDeviceWindow = objc_getClass("_TtC9Simulator12DeviceWindow");
    Class _SimulatorAppDelegate = objc_getClass("SimulatorAppDelegate");
    if (!_SimulatorDeviceWindow || !_SimulatorAppDelegate) {
        NSLog(@"Failed to find Simulator classes");
        return;
    }
    
    // -[NSBundle mainBundle] needs to return Simulator.app's real bundle
    Method mainBundleMethod = class_getClassMethod([NSBundle class], @selector(mainBundle));
    IMP originalMainBundleIMP = method_getImplementation(mainBundleMethod);
    IMP swizzledMainBundleIMP = imp_implementationWithBlock(^(id _self) {
        NSBundle *simulatorBundle = [NSBundle bundleWithPath:[self simulatorBundlePath]];
        if (simulatorBundle) {
            return simulatorBundle;
        }

        return ((NSBundle *(*)(id, SEL))originalMainBundleIMP)(_self, @selector(mainBundle));
    });
    method_setImplementation(mainBundleMethod, swizzledMainBundleIMP);
    
    // Override some NSUserDefaults preferences
    Method boolForKeyMethod = class_getInstanceMethod([NSUserDefaults class], @selector(boolForKey:));
    IMP originalBoolForKeyIMP = method_getImplementation(boolForKeyMethod);
    IMP swizzledBoolForKeyIMP = imp_implementationWithBlock(^(id _self, NSString *key) {
        if ([@[@"CarPlayExtraOptions", @"DebugLogging"] containsObject:key]) {
            return YES;
        }
        
        return ((BOOL (*)(id, SEL, NSString *))originalBoolForKeyIMP)(_self, @selector(boolForKey:), key);
    });
    method_setImplementation(boolForKeyMethod, swizzledBoolForKeyIMP);
    
    // Swizzle file drag-and-drop operation to add support for debs/tweaks
    Method performDragOperationMethod = class_getInstanceMethod(_SimulatorDeviceWindow, sel_registerName("performDragOperation:"));
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

        return ((BOOL (*)(id, SEL, id))originalPerformDragOperationIMP)(_self, sel_registerName("performDragOperation:"), sender);
    });
    method_setImplementation(performDragOperationMethod, newPerformDragOperationIMP);
    
    // Create Simulator's AppDelegate, trigger applicationDidFinishLaunching flow (does a bunch of setup)
    self.simulatorDelegate = [[_SimulatorAppDelegate alloc] init];
    ((void (*)(id, SEL, id))objc_msgSend)(self.simulatorDelegate, sel_registerName("applicationDidFinishLaunching:"), nil);
    
    // Load the MainMenu.xib from Simulator.app bundle. This populates the menu bar with the Simulator's menu items
    NSBundle *simBundle = [NSBundle bundleWithPath:[self simulatorBundlePath]];
    NSArray *topObjects = nil;
    [simBundle loadNibNamed:@"MainMenu" owner:NSApp topLevelObjects:&topObjects];
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
