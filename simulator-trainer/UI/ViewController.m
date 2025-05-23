//
//  ViewController.m
//  simulator-trainer
//
//  Created by Ethan Arbuckle on 4/28/25.
//

#import "BootedSimulatorWrapper.h"
#import "HelperConnection.h"
#import "SimHelperCommon.h"
#import "ViewController.h"
#import "SimLogging.h"

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
    
    [self _populateDevicePopup];
    [self refreshDeviceList];
}

- (void)refreshDeviceList {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // Reload the list of devices
        BOOL isFirstFetch = (self->allSimDevices == nil);
        self->allSimDevices = [BootedSimulatorWrapper allDevices];
        
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

    NSXPCConnection *conn = [self->helperConnection getConnection];
    if (!conn) {
        [self device:bootedSim jailbreakFinished:NO error:[NSError errorWithDomain:NSCocoaErrorDomain code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Failed to connect to helper"}]];
        return;
    }
    
    [[conn remoteObjectProxyWithErrorHandler:^(NSError * _Nonnull proxyError) {
        [self device:bootedSim jailbreakFinished:NO error:proxyError];
    }] mountTmpfsOverlaysAtPaths:[bootedSim directoriesToOverlay] completion:^(NSError *error) {
        if (error) {
            NSString *errorMessage = [NSString stringWithFormat:@"Failed to mount tmpfs overlays: %@", error];
            [self device:bootedSim jailbreakFinished:NO error:[NSError errorWithDomain:NSCocoaErrorDomain code:-1 userInfo:@{NSLocalizedDescriptionKey: errorMessage}]];
        }
        else {
            [self _helper_didMountOverlaysOnDevice:bootedSim];
        }
    }];
}

- (void)_helper_didMountOverlaysOnDevice:(BootedSimulatorWrapper *)bootedSim {
    NSXPCConnection *conn = [self->helperConnection getConnection];
    if (!conn) {
        [self device:bootedSim jailbreakFinished:NO error:[NSError errorWithDomain:NSCocoaErrorDomain code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Failed to connect to helper"}]];
        return;
    }
    
    SimInjectionOptions *options = [[SimInjectionOptions alloc] init];
    options.tweakLoaderDestinationPath = [bootedSim tweakLoaderDylibPath];
    options.victimPathForTweakLoader = [bootedSim libObjcPath];
    options.tweakLoaderSourcePath = [[NSBundle mainBundle] pathForResource:@"loader" ofType:@"dylib"];
    options.optoolPath = [[NSBundle mainBundle] pathForResource:@"optool" ofType:nil];
    options.filesToCopy = bootedSim.bootstrapFilesToCopy;

    [[conn remoteObjectProxyWithErrorHandler:^(NSError * _Nonnull proxyError) {
        [self device:bootedSim jailbreakFinished:NO error:proxyError];
    }] setupTweakInjectionWithOptions:options completion:^(NSError *error) {
        [bootedSim reloadDeviceState];

        BOOL jbSuccess = !error && [bootedSim isJailbroken];
        [self device:bootedSim jailbreakFinished:jbSuccess error:error];
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

@end
