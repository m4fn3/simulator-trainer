//
//  ViewController.m
//  simulator-trainer
//
//  Created by Ethan Arbuckle on 4/28/25.
//

#import "BootedSimulatorWrapper.h"
#import "SimInjectionOptions.h"
#import "HelperConnection.h"
#import "SimDeviceManager.h"
#import "ViewController.h"
#import "CommandRunner.h"
#import "XCRunInterface.h"
#import "SimLogging.h"
#import "platform_changer.h"
#import "AppBinaryPatcher.h"

#define ON_MAIN_THREAD(block) \
    if ([[NSThread currentThread] isMainThread]) { \
        block(); \
    } else { \
        dispatch_sync(dispatch_get_main_queue(), block); \
    }

@interface ViewController () {
    NSArray *allSimDevices;
    SimulatorWrapper *selectedDevice;
    NSInteger selectedDeviceIndex;
    HelperConnection *helperConnection;
}

@end

@implementation ViewController

- (instancetype)initWithCoder:(NSCoder *)coder {
    if ((self = [super initWithCoder:coder])) {
        allSimDevices = nil;
        selectedDevice = nil;
        selectedDeviceIndex = -1;
        helperConnection = [[HelperConnection alloc] init];
        
        [SimLogging observeSimulatorLogs];
    }

    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.devicePopup.target = self;
    self.devicePopup.action = @selector(popupListDidSelectDevice:);
    
    self.jailbreakButton.target = self;
    self.jailbreakButton.action = @selector(handleDoJailbreakSelected:);
    
    self.removeJailbreakButton.target = self;
    self.removeJailbreakButton.action = @selector(handleRemoveJailbreakSelected:);
    
    self.rebootButton.target = self;
    self.rebootButton.action = @selector(handleRebootSelected:);
    
    self.respringButton.target = self;
    self.respringButton.action = @selector(handleRespringSelected:);
    
    self.bootButton.target = self;
    self.bootButton.action = @selector(handleBootSelected:);
    
    self.shutdownButton.target = self;
    self.shutdownButton.action = @selector(handleShutdownSelected:);
    
    self.installTweakButton.acceptedFileExtensions = @[@"deb"];
    self.installTweakButton.target = self;
    self.installTweakButton.action = @selector(handleInstallTweakSelected:);
    __weak typeof(self) weakSelf = self;
    self.installTweakButton.fileDroppedBlock = ^(NSURL *fileURL) {
        [weakSelf processDebFileAtURL:fileURL];
    };
    
    [self _populateDevicePopup];
    [self refreshDeviceList];
}

- (void)refreshDeviceList {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // Reload the list of devices
        BOOL isFirstFetch = (self->allSimDevices == nil);
        self->allSimDevices = [SimDeviceManager buildDeviceList];
        
        ON_MAIN_THREAD(^{
            // Update the device list UI whenever the list changes
            [self _populateDevicePopup];
            
            // A device needs to be preselected for the initial load, before the user has a chance to select one themselves.
            // If this is the first load, signaled by the device list being empty which only occurs the first time devices are loaded,
            // then autoselect the best device in the popup list
            if (isFirstFetch) {
                [self _autoselectDevice];
            }
        });
    });
}

- (void)_populateDevicePopup {    
    // Purge the device selection list, then rebuild it using the devices currently in allSimDevices
    [self.devicePopup removeAllItems];
    NSArray *deviceList = self->allSimDevices;
    
    // If no devices were found
    if (deviceList.count == 0) {
        [self.devicePopup addItemWithTitle:@"-- None --"];
        [self.devicePopup selectItemAtIndex:0];
        [self.devicePopup setEnabled:NO];
        return;
    }
    
    // Otherwise, add each discovered device to the popup list
    for (int i = 0; i < deviceList.count; i++) {
        SimulatorWrapper *device = deviceList[i];
        // displayString: "(Booted) iPhone 14 Pro (iOS 17.0) [A1B2C3D4-5678-90AB-CDEF-1234567890AB]"
        [self.devicePopup addItemWithTitle:[device displayString]];
    }
    
    // If a device has already been selected from the popup list, and
    // that device is still available in the popup list after rebuilding it, then
    // reselect that device
    if (self->selectedDevice && (self->selectedDeviceIndex >= 0 && self->selectedDeviceIndex < self.devicePopup.numberOfItems)) {
        NSMenuItem *selectedItem = [self.devicePopup itemAtIndex:self->selectedDeviceIndex];
        
        // Sanity check its the right device
        if ([selectedItem.title isEqualToString:[self->selectedDevice displayString]]) {
            [self.devicePopup selectItem:selectedItem];
        }
        else {
            NSLog(@"Selected device not found in list!");
            [self.devicePopup selectItemAtIndex:0];
        }
    }
    else {
        [self.devicePopup selectItemAtIndex:0];
    }

    [self.devicePopup setEnabled:YES];
}

- (void)_updateDeviceMenuItemLabels {
    // For every device in the popup list, refresh the coresimulator state then update the label's text.
    // This is necessary because the text includes the device's current boot state
    __weak typeof(self) weakSelf = self;
    ON_MAIN_THREAD(^{
        for (int i = 0; i < weakSelf.devicePopup.numberOfItems; i++) {
            NSMenuItem *item = [weakSelf.devicePopup itemAtIndex:i];

            SimulatorWrapper *device = self->allSimDevices[i];
            NSString *oldDeviceLabel = item.title;
            
            // Reload the sim device's state
            [device reloadDeviceState];
            
            // Update the label with the potentially-changed displayString
            NSString *newDeviceLabel = [device displayString];
            if (![oldDeviceLabel isEqualToString:newDeviceLabel]) {
                [item setTitle:newDeviceLabel];
            }
        }
    });
}

- (void)_autoselectDevice {
    NSInteger selectedDeviceIndex = 0;
    // Default selection goes to the first-encountered jailbroken booted device, falling
    // back to the last-encountered booted device, falling back to the first-encountered
    // iOS-platform device, with the last resort being to just select the first device
    for (int i = 0; i < allSimDevices.count; i++) {
        SimulatorWrapper *device = allSimDevices[i];
        if (device.isBooted && [device isKindOfClass:[BootedSimulatorWrapper class]] && [(BootedSimulatorWrapper *)device hasInjection]) {
            selectedDeviceIndex = i;
            break;
        }
        else if (device.isBooted) {
            selectedDeviceIndex = i;
        }
        else if (!selectedDeviceIndex && [device.platform isEqualToString:@"iOS"]) {
            selectedDeviceIndex = i;
        }
    }
    
    if (selectedDeviceIndex < 0 || selectedDeviceIndex >= allSimDevices.count) {
        NSLog(@"Invalid device index: %ld", (long)selectedDeviceIndex);
        return;
    }

    [self.devicePopup selectItemAtIndex:selectedDeviceIndex];
    [self popupListDidSelectDevice:self.devicePopup];
}

- (void)_updateSelectedDeviceUI {
    ON_MAIN_THREAD(^{
        // Update the device buttons and labels based on the selected device
        if (!self->selectedDevice) {
            // No device selected -- disable buttons
            [self disableDeviceButtons];
            return;
        }
        
        // Start with everything disabled
        [self disableDeviceButtons];
        
        self.statusImageView.image = [NSImage imageNamed:NSImageNameStatusUnavailable];
        self.tweakStatus.stringValue = @"No active device";
        
        if (self->selectedDevice.isBooted) {
            // Booted device: enable reboot and check for jailbreak
            self.rebootButton.enabled = YES;
            self.shutdownButton.enabled = YES;
            
            BootedSimulatorWrapper *bootedSim = [BootedSimulatorWrapper fromSimulatorWrapper:self->selectedDevice];
            if ([bootedSim isJailbroken]) {
                // Device is jailbroken
                self.removeJailbreakButton.enabled = YES;
                self.respringButton.enabled = YES;
                self.installIPAButton.enabled = YES;
                self.installTweakButton.enabled = YES;
                self.statusImageView.image = [NSImage imageNamed:NSImageNameStatusAvailable];
                self.tweakStatus.stringValue = @"Injection active";
            }
            else {
                // Device is not jailbroken
                self.jailbreakButton.enabled = YES;
                self.installIPAButton.enabled = YES;
                self.statusImageView.image = [NSImage imageNamed:NSImageNameStatusPartiallyAvailable];
                self.tweakStatus.stringValue = @"Simulator not jailbroken";
            }
        }
        else {
            // Device is not booted: enable boot button
            self.bootButton.enabled = YES;
            self.rebootButton.enabled = NO;
            self.shutdownButton.enabled = NO;
        }
    });
}

- (void)popupListDidSelectDevice:(NSPopUpButton *)sender {
    // The user selected a device from the popup list
    if (self->allSimDevices.count == 0) {
        [self setStatus:@"Bad selection"];
        NSLog(@"There are no devices but you selected a device ?? Sender: %@", sender);
        return;
    }
    
    // The selection index is the index of the chosen device in the allSimDevices list
    NSInteger selectedIndex = [self.devicePopup indexOfSelectedItem];
    if (selectedIndex == -1 || selectedIndex >= self->allSimDevices.count) {
        NSLog(@"Selected an invalid device index: %ld. Expected range is 0-%lu", (long)selectedIndex, (unsigned long)self->allSimDevices.count);
        return;
    }
    
    SimulatorWrapper *newlySelectedDevice = self->allSimDevices[selectedIndex];
    if (newlySelectedDevice.isBooted) {
        newlySelectedDevice = [BootedSimulatorWrapper fromSimulatorWrapper:newlySelectedDevice];
    }
    
    // Only log if a device is already selected (i.e. this isn't the initial load's autoselect), and
    // the new selection is different from the previous selection
    SimulatorWrapper *previouslySelectedDevice = self->selectedDevice;
    if (previouslySelectedDevice  && previouslySelectedDevice != newlySelectedDevice) {
        NSLog(@"Selected device: %@", newlySelectedDevice);
    }
    self->selectedDevice = newlySelectedDevice;

    // The device delegate is notified of state changes to the device (boot/shutdown/failures)
    self->selectedDevice.delegate = self;
    self->selectedDeviceIndex = selectedIndex;
    
    // Refresh the device's state then update the device-specific UI stuff (buttons, labels)
    [self->selectedDevice reloadDeviceState];
    [self _updateSelectedDeviceUI];
}

- (void)handleRebootSelected:(NSButton *)sender {
    if (!self->selectedDevice) {
        [self setStatus:@"Nothing selected"];
        return;
    }
    
    if (!self->selectedDevice.isBooted) {
        [self setStatus:@"Device not booted"];
        return;
    }
    
    NSLog(@"Rebooting device: %@", self->selectedDevice);
    BootedSimulatorWrapper *bootedSim = [BootedSimulatorWrapper fromSimulatorWrapper:self->selectedDevice];
    [bootedSim reboot];
}

- (void)handleBootSelected:(NSButton *)sender {
    if (!self->selectedDevice) {
        [self setStatus:@"Nothing selected"];
        return;
    }
    
    if (self->selectedDevice.isBooted) {
        [self setStatus:@"Already booted"];
        return;
    }
    
    [self setStatus:@"Booting device"];
    [self->selectedDevice bootWithCompletion:nil];
}

- (void)handleShutdownSelected:(NSButton *)sender {
    if (!self->selectedDevice) {
        [self setStatus:@"Nothing selected"];
        return;
    }
    
    if (!self->selectedDevice.isBooted) {
        [self setStatus:@"Device not booted"];
        return;
    }
    
    [self setStatus:@"Shutting down device"];

    BootedSimulatorWrapper *bootedSim = [BootedSimulatorWrapper fromSimulatorWrapper:self->selectedDevice];
    [bootedSim shutdownWithCompletion:nil];
}

- (void)disableDeviceButtons {
    self.jailbreakButton.enabled = NO;
    self.removeJailbreakButton.enabled = NO;
    self.rebootButton.enabled = NO;
    self.respringButton.enabled = NO;
    self.installIPAButton.enabled = NO;
    self.installTweakButton.enabled = NO;
    self.bootButton.enabled = NO;
    self.shutdownButton.enabled = NO;
}

- (void)handleDoJailbreakSelected:(NSButton *)sender {
    if (!self->selectedDevice) {
        [self setStatus:@"Nothing selected"];
        return;
    }
    
    if (!self->selectedDevice.isBooted) {
        [self setStatus:@"Device not booted"];
        return;
    }
    
    BootedSimulatorWrapper *bootedSim = [BootedSimulatorWrapper fromSimulatorWrapper:self->selectedDevice];
    if ([bootedSim isJailbroken]) {
        [self setStatus:@"Device already jailbroken"];
        return;
    }
    
    self.jailbreakButton.enabled = NO;
    [self setStatus:@"Jailbreaking..."];

    [self->helperConnection mountTmpfsOverlaysAtPaths:[bootedSim directoriesToOverlay] completion:^(NSError *error) {
        if (error) {
            [self device:bootedSim jailbreakFinished:NO error:error];
        }
        else {
            [self _helper_didMountOverlaysOnDevice:bootedSim];
        }
    }];
}

- (void)_helper_didMountOverlaysOnDevice:(BootedSimulatorWrapper *)bootedSim {
    SimInjectionOptions *options = [[SimInjectionOptions alloc] init];
    options.tweakLoaderDestinationPath = [bootedSim tweakLoaderDylibPath];
    options.victimPathForTweakLoader = [bootedSim libObjcPath];
    options.tweakLoaderSourcePath = [[NSBundle mainBundle] pathForResource:@"loader" ofType:@"dylib"];
    options.optoolPath = [[NSBundle mainBundle] pathForResource:@"optool" ofType:nil];
    options.filesToCopy = bootedSim.bootstrapFilesToCopy;

    [self->helperConnection setupTweakInjectionWithOptions:options completion:^(NSError *error) {
        if (error) {
            [self device:bootedSim jailbreakFinished:NO error:error];
        }
        else {
            [bootedSim reloadDeviceState];

            BOOL jbSuccess = !error && [bootedSim isJailbroken];
            [self device:bootedSim jailbreakFinished:jbSuccess error:error];
        }
    }];
}

- (void)handleRemoveJailbreakSelected:(NSButton *)sender {
    if (!self->selectedDevice) {
        [self setStatus:@"Nothing selected"];
        return;
    }
    
    if (!self->selectedDevice.isBooted) {
        [self setStatus:@"Device not booted"];
        return;
    }
    
    BootedSimulatorWrapper *bootedSim = [BootedSimulatorWrapper fromSimulatorWrapper:self->selectedDevice];
    if (![bootedSim isJailbroken]) {
        [self setStatus:@"Device not jailbroken"];
        return;
    }

    self.removeJailbreakButton.enabled = NO;
    self.jailbreakButton.enabled = NO;
    self.statusImageView.image = [NSImage imageNamed:NSImageNameStatusPartiallyAvailable];
    
    NSXPCConnection *conn = [self->helperConnection getConnection];
    [[conn remoteObjectProxyWithErrorHandler:^(NSError * _Nonnull proxyError) {
        NSLog(@"Unjailbreak remoteObjectProxyWithErrorHandler error: %@", proxyError);
        [self setStatus:@"Failed to connect to helper"];
        
        [self refreshDeviceList];
        
    }] unmountMountPoints:[bootedSim directoriesToOverlay] completion:^(NSError *unmountError) {
        if (unmountError) {
            NSLog(@"Unjailbreak unmountMountPoints error: %@", unmountError);
            [self setStatus:@"Failed to unmount overlays"];
            
            [self refreshDeviceList];
        }

        [bootedSim shutdownWithCompletion:^(NSError *shutdownError) {
            if (shutdownError) {
                NSLog(@"Unjailbreak shutdownWithCompletion error: %@", shutdownError);
                [self setStatus:@"Failed to shutdown device"];
                
                [self refreshDeviceList];
            }

            [bootedSim bootWithCompletion:^(NSError *bootError) {
                [self setStatus:@"Jailbreak removed"];
                [self refreshDeviceList];
                [self _updateSelectedDeviceUI];
            }];
        }];
    }];
}

- (void)handleRespringSelected:(NSButton *)sender {
    NSLog(@"Respring selected");
    if (!self->selectedDevice) {
        [self setStatus:@"Nothing selected"];
        return;
    }
    
    if (!self->selectedDevice.isBooted) {
        [self setStatus:@"Device not booted"];
        return;
    }
    
    BootedSimulatorWrapper *bootedSim = [BootedSimulatorWrapper fromSimulatorWrapper:self->selectedDevice];
    [bootedSim respring];
}

- (void)setStatus:(NSString *)statusText {
    __weak typeof(self) weakSelf = self;
    ON_MAIN_THREAD(^{
        weakSelf.tweakStatus.stringValue = statusText;
    });
}

#pragma mark - SimulatorWrapperDelegate

- (void)deviceDidBoot:(SimulatorWrapper *)simDevice {
    NSLog(@"Device did boot: %@", simDevice);
    self->selectedDevice = simDevice;
    self->selectedDevice.delegate = self;
    
    [self _updateSelectedDeviceUI];
    [self _updateDeviceMenuItemLabels];

    __weak typeof(self) weakSelf = self;
    ON_MAIN_THREAD(^{
        weakSelf.bootButton.enabled = NO;
        weakSelf.rebootButton.enabled = YES;
        weakSelf.shutdownButton.enabled = YES;
    });
}

- (void)deviceDidReboot:(SimulatorWrapper *)simDevice {
    NSLog(@"Device did reboot: %@", simDevice);
    if (!self->selectedDevice) {
        return;
    }

    __weak typeof(self) weakSelf = self;
    ON_MAIN_THREAD(^{
        [self _updateSelectedDeviceUI];
        [self _updateDeviceMenuItemLabels];
        
        weakSelf.bootButton.enabled = NO;
        weakSelf.rebootButton.enabled = YES;
        weakSelf.shutdownButton.enabled = YES;
    });
}

- (void)deviceDidShutdown:(SimulatorWrapper *)simDevice {
    NSLog(@"Device did shutdown: %@", simDevice);
    __weak typeof(self) weakSelf = self;
    ON_MAIN_THREAD(^{
        [self _updateSelectedDeviceUI];
        [self _updateDeviceMenuItemLabels];

        weakSelf.bootButton.enabled = YES;
        weakSelf.rebootButton.enabled = NO;
        weakSelf.shutdownButton.enabled = NO;
        weakSelf.removeJailbreakButton.enabled = NO;
        weakSelf.respringButton.enabled = NO;
        weakSelf.installIPAButton.enabled = NO;
        weakSelf.installTweakButton.enabled = NO;
    });
}

- (void)device:(SimulatorWrapper *)simDevice didFailToBootWithError:(NSError * _Nullable)error {
    NSLog(@"Device failed to boot: %@", error);
    [self _updateDeviceMenuItemLabels];
}

- (void)device:(SimulatorWrapper *)simDevice didFailToShutdownWithError:(NSError * _Nullable)error {
    NSLog(@"Device failed to shutdown: %@", error);
    [self _updateDeviceMenuItemLabels];
}

- (void)device:(SimulatorWrapper *)simDevice jailbreakFinished:(BOOL)success error:(NSError * _Nullable)error {
    __weak typeof(self) weakSelf = self;
    ON_MAIN_THREAD(^{
        if (error || !success) {
            weakSelf.jailbreakButton.enabled = YES;
            NSLog(@"Failed to jailbreak device with error: %@", error);
            [self setStatus:@"Failed to jailbreak sim device"];
        }
        else if (success) {
            weakSelf.jailbreakButton.enabled = NO;
            weakSelf.removeJailbreakButton.enabled = YES;
            [self setStatus:@"Sim device is jailbroken"];
            
            BootedSimulatorWrapper *bootedSim = [BootedSimulatorWrapper fromSimulatorWrapper:simDevice];
            [bootedSim respring];
        }
        
        [self _updateSelectedDeviceUI];
    });
}

- (void)processDebFileAtURL:(NSURL *)debURL {
    NSLog(@"Processing deb file: %@", debURL);
    if (!selectedDevice || !selectedDevice.isBooted) {
        [self setStatus:@"Please select a booted device first."];
        return;
    }
    
    BootedSimulatorWrapper *bootedSim = [BootedSimulatorWrapper fromSimulatorWrapper:selectedDevice];
    if (!bootedSim) {
        [self setStatus:@"Selected device is not properly booted."];
        return;
    }

    [self setStatus:[NSString stringWithFormat:@"Installing %@...", debURL.lastPathComponent]];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSError *installError = [self _installExtractedTweakFilesFromDebPath:debURL.path toSimulatorRuntime:bootedSim.runtimeRoot];
        ON_MAIN_THREAD((^{
            if (installError) {
                [self setStatus:[NSString stringWithFormat:@"Install failed: %@", installError.localizedDescription]];
            }
            else {
                [self setStatus:@"Installed"];
                [self _updateSelectedDeviceUI];
            }
        }));
    });
}


- (void)handleInstallTweakSelected:(id)sender {
    if (!selectedDevice || !selectedDevice.isBooted) {
        [self setStatus:@"Nothing selected"];
        return;
    }
    
    NSOpenPanel *openPanel = [NSOpenPanel openPanel];
    openPanel.canChooseFiles = YES;
    openPanel.canChooseDirectories = NO;
    openPanel.allowsMultipleSelection = NO;
    openPanel.allowedFileTypes = @[@"deb"];
    
    [openPanel beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK) {
            NSURL *debURL = openPanel.URL;
            if (debURL) {
                [self processDebFileAtURL:debURL];
            }
        }
    }];
}

- (NSError * _Nullable)_installExtractedTweakFilesFromDebPath:(NSString *)debPath toSimulatorRuntime:(NSString *)simRuntimeRoot {
    if (!simRuntimeRoot) {
        return [NSError errorWithDomain:NSCocoaErrorDomain code:98 userInfo:@{NSLocalizedDescriptionKey: @"Simulator runtime root path is nil."}];
    }
    
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *tempExtractDir = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    NSString *dataTarExtractDir = [tempExtractDir stringByAppendingPathComponent:@"data_payload"];
    NSError * __block operationError = nil;
    
    if (![fm createDirectoryAtPath:tempExtractDir withIntermediateDirectories:YES attributes:nil error:&operationError]) {
        return operationError;
    }
    
    void (^cleanupBlock)(void) = ^{
        [fm removeItemAtPath:tempExtractDir error:nil];
    };
    
    NSString *debFileName = [debPath lastPathComponent];
    NSString *copiedDebPath = [tempExtractDir stringByAppendingPathComponent:debFileName];
    if (![fm copyItemAtPath:debPath toPath:copiedDebPath error:&operationError]) {
        cleanupBlock();
        return operationError;
    }
    
    if (![CommandRunner runCommand:@"/usr/bin/ar" withArguments:@[@"-x", copiedDebPath] cwd:tempExtractDir stdoutString:nil error:&operationError]) {
        cleanupBlock();
        return operationError ?: [NSError errorWithDomain:NSCocoaErrorDomain code:101 userInfo:@{NSLocalizedDescriptionKey: @"Failed to extract .deb (ar command)"}];
    }

    NSString *dataTarName = nil;
    NSArray *possibleDataTarNames = @[@"data.tar.gz", @"data.tar.xz", @"data.tar.zst", @"data.tar.bz2", @"data.tar,", @"data.tar.lzma"];
    for (NSString *name in possibleDataTarNames) {
        if ([fm fileExistsAtPath:[tempExtractDir stringByAppendingPathComponent:name]]) {
            dataTarName = name;
            break;
        }
    }
    
    if (!dataTarName) {
        cleanupBlock();
        return [NSError errorWithDomain:NSCocoaErrorDomain code:100 userInfo:@{NSLocalizedDescriptionKey: @"Could not find data.tar.* in .deb archive"}];
    }
    
    NSString *dataTarPath = [tempExtractDir stringByAppendingPathComponent:dataTarName];
    if (![fm createDirectoryAtPath:dataTarExtractDir withIntermediateDirectories:YES attributes:nil error:&operationError]) {
        cleanupBlock();
        return operationError;
    }
    
    if (![CommandRunner runCommand:@"/usr/bin/tar" withArguments:@[@"-xf", dataTarPath, @"-C", dataTarExtractDir] stdoutString:nil error:&operationError]) {
        cleanupBlock();
        return operationError ?: [NSError errorWithDomain:NSCocoaErrorDomain code:102 userInfo:@{NSLocalizedDescriptionKey: @"Failed to extract data.tar (tar command)"}];
    }
    
    NSDirectoryEnumerator *dirEnumerator = [fm enumeratorAtPath:dataTarExtractDir];
    NSString *fileRelativeInDataTar;
    while ((fileRelativeInDataTar = [dirEnumerator nextObject])) {
        NSString *sourcePath = [dataTarExtractDir stringByAppendingPathComponent:fileRelativeInDataTar];
        
        BOOL isDir;
        if ([fm fileExistsAtPath:sourcePath isDirectory:&isDir] && !isDir) {
            NSString *cleanedRelativePath = [fileRelativeInDataTar copy];
            if ([cleanedRelativePath hasPrefix:@"./"]) {
                cleanedRelativePath = [cleanedRelativePath substringFromIndex:2];
            }
            
            NSString *destinationPath = [simRuntimeRoot stringByAppendingPathComponent:cleanedRelativePath];
            NSString *destinationParentDir = [destinationPath stringByDeletingLastPathComponent];
            
            if (![fm fileExistsAtPath:destinationParentDir]) {
                if (![fm createDirectoryAtPath:destinationParentDir withIntermediateDirectories:YES attributes:nil error:&operationError]) {
                    cleanupBlock();
                    return operationError;
                }
            }
            
            if ([fm fileExistsAtPath:destinationPath]) {
                [fm removeItemAtPath:destinationPath error:NULL];
            }
            
            if (![fm copyItemAtPath:sourcePath toPath:destinationPath error:&operationError]) {
                NSLog(@"  copy error: %@", operationError);
                cleanupBlock();
                return operationError;
            }
            
            if ([destinationPath.pathExtension isEqualToString:@"dylib"] && ![AppBinaryPatcher isBinaryArm64SimulatorCompatible:destinationPath]) {
                // Convert to simulator platform and then codesign
                [AppBinaryPatcher thinBinaryAtPath:destinationPath];
                convertPlatformToSimulator(destinationPath.UTF8String);
                
                [AppBinaryPatcher codesignItemAtPath:destinationPath completion:^(BOOL success, NSError *error) {
                    if (!success) {
                        NSLog(@"Failed to codesign item at path: %@", error);
                    }
                    else {
                        NSLog(@"Successfully codesigned item at path: %@", destinationPath);
                    }
                }];
            }
        }
    }

    cleanupBlock();
    return nil;
}


@end
