//
//  ViewController.m
//  simulator-trainer
//
//  Created by Ethan Arbuckle on 4/28/25.
//

#import "SimulatorOrchestrationService.h"
#import "InProcessSimulator.h"
#import "HelperConnection.h"
#import "SimDeviceManager.h"
#import "ViewController.h"

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
    SimulatorOrchestrationService *orchestrator;
}

@property (nonatomic, strong) InProcessSimulator *simInterposer;
@property (nonatomic, strong) id simDeviceObserver;

@end

@implementation ViewController

- (instancetype)initWithCoder:(NSCoder *)coder {
    if ((self = [super initWithCoder:coder])) {
        allSimDevices = nil;
        selectedDevice = nil;
        selectedDeviceIndex = -1;
        helperConnection = [[HelperConnection alloc] init];
        orchestrator = [[SimulatorOrchestrationService alloc] initWithHelperConnection:helperConnection];
        
        self.packageService = [[PackageInstallationService alloc] init];
        self.simInterposer = [InProcessSimulator sharedSetupIfNeeded];
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
    
    self.openTweakFolderButton.target = self;
    self.openTweakFolderButton.action = @selector(handleOpenTweakFolderSelected:);
    
    self.installTweakButton.acceptedFileExtensions = @[@"deb"];
    self.installTweakButton.target = self;
    self.installTweakButton.action = @selector(handleInstallTweakSelected:);
    __weak typeof(self) weakSelf = self;
    self.installTweakButton.fileDroppedBlock = ^(NSURL *fileURL) {
        [weakSelf processDebFileAtURL:fileURL];
    };
    
    [NSNotificationCenter.defaultCenter addObserverForName:@"InstallTweakNotification" object:nil queue:nil usingBlock:^(NSNotification * _Nonnull notification) {
        NSString *debPath = notification.object;
        if (!debPath || debPath.length == 0) {
            return;
        }
        
        [self processDebFileAtURL:[NSURL fileURLWithPath:debPath]];
    }];
    
    void (^deviceListFullRefreshBlock)(void) = ^(void) {
        [self _populateDevicePopup];
        [self refreshDeviceList];
    };
    
    _simDeviceObserver = [NSNotificationCenter.defaultCenter addObserverForName:@"SimDeviceStateChanged" object:nil queue:nil usingBlock:^(NSNotification * _Nonnull notification) {
        NSLog(@"Device list changed, refreshing...");
        deviceListFullRefreshBlock();
        [self _autoselectDevice];
    }];
    
    deviceListFullRefreshBlock();
}

- (void)setStatus:(NSString *)statusText {
    __weak typeof(self) weakSelf = self;
    ON_MAIN_THREAD(^{
        weakSelf.tweakStatus.stringValue = statusText;
    });
}

- (void)_disableDeviceButtons {
    self.jailbreakButton.enabled = NO;
    self.removeJailbreakButton.enabled = NO;
    self.rebootButton.enabled = NO;
    self.respringButton.enabled = NO;
    self.installIPAButton.enabled = NO;
    self.installTweakButton.enabled = NO;
    self.bootButton.enabled = NO;
    self.shutdownButton.enabled = NO;
    self.openTweakFolderButton.enabled = NO;
}

#pragma mark - Device List

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
    __weak typeof(self) weakSelf = self;
    ON_MAIN_THREAD(^{
        // Purge the device selection list, then rebuild it using the devices currently in allSimDevices
        [weakSelf.devicePopup removeAllItems];
        NSArray *deviceList = self->allSimDevices;
        
        // If no devices were found
        if (deviceList.count == 0) {
            [weakSelf.devicePopup addItemWithTitle:@"-- None --"];
            [weakSelf.devicePopup selectItemAtIndex:0];
            [weakSelf.devicePopup setEnabled:NO];
            return;
        }
        
        // Otherwise, add each discovered device to the popup list
        for (int i = 0; i < deviceList.count; i++) {
            SimulatorWrapper *device = deviceList[i];
            // displayString: "(Booted) iPhone 14 Pro (iOS 17.0) [A1B2C3D4-5678-90AB-CDEF-1234567890AB]"
            [weakSelf.devicePopup addItemWithTitle:[device displayString]];
        }
        
        // If a device has already been selected from the popup list, and
        // that device is still available in the popup list after rebuilding it, then
        // reselect that device
        if (self->selectedDevice && (self->selectedDeviceIndex >= 0 && self->selectedDeviceIndex < weakSelf.devicePopup.numberOfItems)) {
            NSMenuItem *selectedItem = [weakSelf.devicePopup itemAtIndex:self->selectedDeviceIndex];
            
            // Sanity check its the right device
            if ([selectedItem.title isEqualToString:[self->selectedDevice displayString]]) {
                [weakSelf.devicePopup selectItem:selectedItem];
            }
            else {
                NSLog(@"Selected device not found in list!");
                [weakSelf.devicePopup selectItemAtIndex:0];
            }
        }
        else {
            [weakSelf.devicePopup selectItemAtIndex:0];
        }
        
        [weakSelf.devicePopup setEnabled:YES];
    });
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
    __weak typeof(self) weakSelf = self;
    ON_MAIN_THREAD(^{
        NSInteger selectedDeviceIndex = 0;
        // Default selection goes to the first-encountered jailbroken booted device, falling
        // back to the last-encountered booted device, falling back to the first-encountered
        // iOS-platform device, with the last resort being to just select the first device
        for (int i = 0; i < self->allSimDevices.count; i++) {
            SimulatorWrapper *device = self->allSimDevices[i];
            if (device.isBooted && [device isKindOfClass:[BootedSimulatorWrapper class]] && [(BootedSimulatorWrapper *)device isJailbroken]) {
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
        
        if (selectedDeviceIndex < 0 || selectedDeviceIndex >= self->allSimDevices.count) {
            NSLog(@"Invalid device index: %ld", (long)selectedDeviceIndex);
            return;
        }
        
        [weakSelf.devicePopup selectItemAtIndex:selectedDeviceIndex];
        [self popupListDidSelectDevice:weakSelf.devicePopup];
    });
}

- (void)_updateSelectedDeviceUI {
    ON_MAIN_THREAD(^{
        // Update the device buttons and labels based on the selected device
        if (!self->selectedDevice) {
            // No device selected -- disable buttons
            [self _disableDeviceButtons];
            return;
        }
        
        // Start with everything disabled
        [self _disableDeviceButtons];
        
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
                self.openTweakFolderButton.enabled = YES;
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

#pragma mark - Button handlers

- (void)handleRebootSelected:(NSButton *)sender {
    [self setStatus:@"Rebooting device"];
    [self->orchestrator rebootDevice:(BootedSimulatorWrapper *)self->selectedDevice completion:^(NSError *error) {
        if (error) {
            [self setStatus:[NSString stringWithFormat:@"Failed to reboot: %@", error]];
        }
    }];
}

- (void)handleBootSelected:(NSButton *)sender {
    [self setStatus:@"Booting"];
    [self->orchestrator bootDevice:self->selectedDevice completion:^(BootedSimulatorWrapper * _Nullable bootedDevice, NSError * _Nullable error) {
        if (error) {
            [self setStatus:[NSString stringWithFormat:@"Failed to boot: %@", error]];
        }
    }];
}

- (void)handleShutdownSelected:(NSButton *)sender {
    [self setStatus:@"Shutting down"];
    BootedSimulatorWrapper *bootedSim = [BootedSimulatorWrapper fromSimulatorWrapper:self->selectedDevice];
    [self->orchestrator shutdownDevice:bootedSim completion:^(NSError *error) {
        if (error) {
            [self setStatus:[NSString stringWithFormat:@"Failed to shutdown: %@", error]];
        }
    }];
}

- (void)handleDoJailbreakSelected:(NSButton *)sender {
    [self setStatus:@"Applying jb..."];
    self.jailbreakButton.enabled = NO;
    BootedSimulatorWrapper *bootedSim = [BootedSimulatorWrapper fromSimulatorWrapper:self->selectedDevice];
    [self->orchestrator applyJailbreakToDevice:bootedSim completion:^(BOOL success, NSError * _Nullable error) {
        [self device:self->selectedDevice jailbreakFinished:success error:error];
    }];
}

- (void)handleRemoveJailbreakSelected:(NSButton *)sender {
    [self setStatus:@"Removing jb..."];
    BootedSimulatorWrapper *bootedSim = [BootedSimulatorWrapper fromSimulatorWrapper:self->selectedDevice];
    [self->orchestrator removeJailbreakFromDevice:bootedSim completion:^(BOOL success, NSError * _Nullable error) {
        ON_MAIN_THREAD((^{
            if (error) {
                [self setStatus:[NSString stringWithFormat:@"Failed to remove jailbreak: %@", error]];
                self.removeJailbreakButton.enabled = YES;
            }
            else {
                [self setStatus:@"Removed jailbreak"];
                self.removeJailbreakButton.enabled = NO;
                self.jailbreakButton.enabled = YES;
            }
        }));
        
        [self refreshDeviceList];
        [self _updateSelectedDeviceUI];
    }];
}

- (void)handleRespringSelected:(NSButton *)sender {
    [self setStatus:@"Respringing device"];
    BootedSimulatorWrapper *bootedSim = [BootedSimulatorWrapper fromSimulatorWrapper:self->selectedDevice];
    [self->orchestrator respringDevice:bootedSim completion:^(NSError * _Nullable error) {
        if (error) {
            [self setStatus:[NSString stringWithFormat:@"Failed to respring: %@", error]];
        }
        else {
            [self _updateSelectedDeviceUI];
        }
    }];
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

- (void)handleOpenTweakFolderSelected:(id)sender {
    if (!selectedDevice || !selectedDevice.isBooted) {
        [self setStatus:@"Nothing selected"];
        return;
    }
    
    BootedSimulatorWrapper *bootedSim = [BootedSimulatorWrapper fromSimulatorWrapper:selectedDevice];
    if (!bootedSim.isJailbroken || !bootedSim.runtimeRoot) {
        [self setStatus:@"Jailbreak not active"];
        return;
    }
    
    NSString *tweakFolder = @"/Library/MobileSubstrate/DynamicLibraries/";
    NSString *deviceTweakFolder = [bootedSim.runtimeRoot stringByAppendingPathComponent:tweakFolder];
    if (![[NSFileManager defaultManager] fileExistsAtPath:deviceTweakFolder]) {
        [self setStatus:[NSString stringWithFormat:@"Tweak folder does not exist: %@", deviceTweakFolder]];
        return;
    }
    
    [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:deviceTweakFolder]];
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

#pragma mark - Tweak Installation
- (void)processDebFileAtURL:(NSURL *)debURL {
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
    [self.packageService installDebFileAtPath:debURL.path toDevice:bootedSim completion:^(NSError * _Nullable error) {
        if (error) {
            NSLog(@"Failed to install deb file: %@", error);
            [self setStatus:[NSString stringWithFormat:@"Install failed: %@", error.localizedDescription]];
        } else {
            [self setStatus:@"Installed"];
            [self _updateSelectedDeviceUI];
        }
    }];
}

@end
