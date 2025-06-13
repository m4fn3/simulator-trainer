//
//  InProcessSimulator.m
//  simulator-trainer
//
//  Created by m1book on 5/28/25.
//

#import <objc/runtime.h>
#import <objc/message.h>
#import <Cocoa/Cocoa.h>
#import <dlfcn.h>
#import "TerminalWindowController.h"
#import "InProcessSimulator.h"
#import "AppBinaryPatcher.h"
#import "dylib_conversion.h"
#import "CycriptLauncher.h"
#import "CommandRunner.h"
#import "SimLogging.h"


@implementation InProcessSimulator

+ (instancetype)sharedSetupIfNeeded {
    static InProcessSimulator *simulatorInterposer = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        
        // Find Simulator.app, make a dylib version that can be loaded in-process
        simulatorInterposer = [[InProcessSimulator alloc] init];
        [simulatorInterposer convertSimulatorToDylibWithCompletion:^(NSString *dylibPath) {
            if (!dylibPath) {
                NSLog(@"Failed to convert Simulator.app to dylib");
                return;
            }
            
            // Handle conflicts before loading the dylib (doesn't involve sim-exclusive classes)
            [simulatorInterposer _patchCriticalSimulatorConflicts];

            [SimLogging observeSimulatorLogs];

            // Load simulator
            if (dlopen([dylibPath UTF8String], 0) == NULL) {
                NSLog(@"Failed to load Simulator dylib: %s", dlerror());
                return;
            }
            
            // With sim loaded in-process, its classes (AppDelegate, view controllers) can be directly modified.
            // Setup drag-and-drop tweak installation
            [simulatorInterposer _setupDragAndDropTweakInstallation];
                        
            // Open the simulator ui
            [simulatorInterposer launchSimulatorFromDylib:dylibPath];
        }];
    });
    
    return simulatorInterposer;
}

- (NSString *)_simulatorBundlePath {
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

- (NSBundle *)_simulatorBundle {
    static NSBundle *simulatorBundle = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *simulatorPath = [self _simulatorBundlePath];
        if (simulatorPath) {
            simulatorBundle = [NSBundle bundleWithPath:simulatorPath];
            if (!simulatorBundle) {
                NSLog(@"Failed to load Simulator.app bundle at path: %@", simulatorPath);
            }
        }
    });
    
    return simulatorBundle;
}

- (void)convertSimulatorToDylibWithCompletion:(void (^)(NSString *dylibPath))completion {
    // Make a copy of the Simulator.app executable at $TMPDIR/Simulator.dylib
    NSString *simulatorExecutablePath = [[self _simulatorBundlePath] stringByAppendingPathComponent:@"Contents/MacOS/Simulator"];
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
        NSArray *simulatorBundlePathComponents = [[self _simulatorBundlePath] pathComponents];
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

- (IMP)_swizzleSelector:(SEL)selector ofClass:(Class)class withBlock:(id)newImpBlock {
    Method method = class_getInstanceMethod(class, selector);
    if (!method) {
        NSLog(@"Failed to find method %@ in class %@", NSStringFromSelector(selector), NSStringFromClass(class));
        return nil;
    }
    
    IMP replacementImp = imp_implementationWithBlock(newImpBlock);
    IMP originalImp = method_getImplementation(method);
    if (originalImp == replacementImp) {
        NSLog(@"Selector %@ already swizzled in class %@", NSStringFromSelector(selector), NSStringFromClass(class));
        return nil;
    }
    
    if (class_replaceMethod(class, selector, replacementImp, method_getTypeEncoding(method)) == NULL) {
        return nil;
    }

    return originalImp;
}

- (BOOL)_patchCriticalSimulatorConflicts {
    // Swizzle +[NSBundle mainBundle] to handle Simulator.dylib expecting to get its own bundle path.
    // It breaks if it receives the real main app (this app) bundle path instead
    NSBundle *simulatorBundle = [self _simulatorBundle];
    
    Class NSBundleClass = objc_getClass("NSBundle");
    SEL mainBundleSel = sel_registerName("mainBundle");
    static IMP origMainBundleImp = nil;
    id (^newMainBundle)(id) = ^(id _self) {
        
        // Get the address of whatever is calling mainBundle, then find the image path for that address.
        // If from the real main executable (this app), return the original main bundle, otherwise return the Simulator bundle
        void *caller = __builtin_return_address(0);
        Dl_info info;
        if (dladdr(caller, &info) && info.dli_fname && strstr(info.dli_fname, "trainer")) {
            return ((NSBundle *(*)(id, SEL))origMainBundleImp)(_self, mainBundleSel);
        }
        
        return simulatorBundle;
    };
    origMainBundleImp = [self _swizzleSelector:mainBundleSel ofClass:object_getClass(NSBundleClass) withBlock:newMainBundle];
    
    // Swizzle NSBundle's objectForInfoDictionaryKey: to return a large CFBundleVersion.
    // There's a Simulator lifecycle arbitrator that may kill this process if it decides
    // an existing running Simulator instance should take priority. It compares versions, then
    // process age (via PID). We will fail the age comparison, so we need to pass the version check
    SEL objectForInfoDictionaryKeySel = sel_registerName("objectForInfoDictionaryKey:");
    static IMP origObjectForInfoDictionaryKeyImp = nil;
    id (^newObjForInfoDict)(id, NSString *) = ^(id _self, NSString *key) {
        if ([key isEqualToString:@"CFBundleVersion"]) {
            return @"99999.0";
        }
        
        return ((NSString * (*)(id, SEL, NSString *))origObjectForInfoDictionaryKeyImp)(_self, objectForInfoDictionaryKeySel, key);
    };
    origObjectForInfoDictionaryKeyImp = [self _swizzleSelector:objectForInfoDictionaryKeySel ofClass:NSBundleClass withBlock:newObjForInfoDict];

    // [NSUserDefaults boolForKey:]
    SEL boolForKeySel = sel_registerName("boolForKey:");
    static IMP origBoolForKeyImp = nil;
    BOOL (^newBoolForKey)(id, NSString *) = ^BOOL(id _self, NSString *key) {
        NSArray *alwaysTrueKeys = @[@"CarPlayExtraOptions"];
        if ([alwaysTrueKeys containsObject:key]) {
            return YES;
        }
        
        return ((BOOL (*)(id, SEL, NSString *))origBoolForKeyImp)(_self, boolForKeySel, key);
    };
    origBoolForKeyImp = [self _swizzleSelector:boolForKeySel ofClass:NSUserDefaults.class withBlock:newBoolForKey];
    
    return YES;
}

- (BOOL)_setupDragAndDropTweakInstallation {
    // This method is called to patch the Simulator's drag-and-drop functionality to support debs/tweaks.
    // It swizzles the performDragOperation: method of the Simulator's DeviceWindow class.
    Class _SimulatorDeviceWindow = objc_getClass("_TtC9Simulator12DeviceWindow");
    SEL performDragOperationSel = sel_registerName("performDragOperation:");
    static IMP origPerformDragOperationImp = nil;
    BOOL (^newPerformDragOperation)(id, id <NSDraggingInfo>) = ^BOOL(id _self, id <NSDraggingInfo> sender) {
        
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
            NSLog(@"Installing a tweak: %@", realPath);
            [[NSNotificationCenter defaultCenter] postNotificationName:@"InstallTweakNotification" object:realPath];
            return YES;
        }
        
        return ((BOOL (*)(id, SEL, id))origPerformDragOperationImp)(_self, performDragOperationSel, sender);
    };
    
    origPerformDragOperationImp = [self _swizzleSelector:performDragOperationSel ofClass:_SimulatorDeviceWindow withBlock:newPerformDragOperation];
    return origPerformDragOperationImp != nil;
}

- (void)launchSimulatorFromDylib:(NSString *)simulatorDylibPath {
    // Create Simulator's AppDelegate, trigger applicationDidFinishLaunching flow (does a bunch of setup)
    Class _SimulatorAppDelegate = objc_getClass("SimulatorAppDelegate");
    self.simulatorDelegate = [[_SimulatorAppDelegate alloc] init];
    ((void (*)(id, SEL, id))objc_msgSend)(self.simulatorDelegate, sel_registerName("applicationDidFinishLaunching:"), nil);
    
    // Load the MainMenu.xib from Simulator.app bundle. This populates the menu bar with the Simulator's menu items
    NSBundle *simBundle = [NSBundle bundleWithPath:[self _simulatorBundlePath]];
    NSArray *topObjects = nil;
    [simBundle loadNibNamed:@"MainMenu" owner:NSApp topLevelObjects:&topObjects];
    for (NSObject *object in topObjects) {
        if (![object isKindOfClass:[NSMenu class]]) {
            continue;
        }
        
        for (NSMenuItem *item in [(NSMenu *)object itemArray]) {
            item.hidden = NO;
        }
    }
            
    NSMenu *mainMenu = [NSApp mainMenu];
    NSMenu *simHacksMenu = [[NSMenu alloc] initWithTitle:@"Sim Hacks"];
    NSMenuItem *placeholder1 = [[NSMenuItem alloc] initWithTitle:@"Open GUI" action:@selector(handleOpenSimForgeGui:) keyEquivalent:@""];
    [placeholder1 setTarget:self];

    NSMenuItem *placeholder2 = [[NSMenuItem alloc] initWithTitle:@"Cycript Terminal" action:@selector(handleOpenCycript:) keyEquivalent:@""];
    [placeholder2 setTarget:self];
    
    [simHacksMenu addItem:placeholder1];
    [simHacksMenu addItem:placeholder2];

    NSMenuItem *simHacksMenuItem = [[NSMenuItem alloc] initWithTitle:@"Sim Hacks" action:nil keyEquivalent:@""];
    [simHacksMenuItem setSubmenu:simHacksMenu];
    [mainMenu addItem:simHacksMenuItem];
}

- (void)handleOpenSimForgeGui:(id)sender {
    [[NSNotificationCenter defaultCenter] postNotificationName:@"SimForgeShowMainWindow" object:nil];
}
    
- (void)handleOpenCycript:(id)sender {
    [CycriptLauncher beginSessionForProcessNamed:@"SpringBoard"];
}

- (id)forwardingTargetForSelector:(SEL)aSelector {
    if ([self.simulatorDelegate respondsToSelector:aSelector]) {
        return self.simulatorDelegate;
    }
    
    return [super forwardingTargetForSelector:aSelector];
}

@end
