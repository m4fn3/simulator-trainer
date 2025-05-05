//
//  ViewController.m
//  simulator-trainer
//
//  Created by Ethan Arbuckle on 4/28/25.
//

#import "ViewController.h"
#import "EABootedSimDevice.h"

@interface ViewController () {
    NSArray *bootedDevices;
    BOOL showDemoData;
}

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    [self setupUI];
    [self refreshDeviceList];
}

- (EABootedSimDevice *)currentDevice {
    if (bootedDevices.count == 0) {
        return nil;
    }
    
    NSInteger selectedIndex = [_devicePopup indexOfSelectedItem];
    if (selectedIndex >= bootedDevices.count) {
        return nil;
    }
    
    return bootedDevices[selectedIndex];
}

- (void)refreshStatusLabels {
    showDemoData = NO;
    
    EABootedSimDevice *simulator = [self currentDevice];
    if (!simulator) {
        _tweakStatus.stringValue = @"No booted simulators";
        [self disableDeviceButtons];
        _statusImageView.image = [NSImage imageNamed:NSImageNameStatusUnavailable];
        return;
    }
    
    if ([simulator hasOverlays] || [simulator hasInjection]) {
        _pwnButton.enabled = NO;
        _removeJailbreakButton.enabled = YES;
        _rebootButton.enabled = YES;
        _respringButton.enabled = YES;
        _installIPAButton.enabled = YES;
        _installTweakButton.enabled = YES;
        _tweakStatus.stringValue = @"Injection active";
        _statusImageView.image = [NSImage imageNamed:NSImageNameStatusAvailable];
        
        showDemoData = YES;
    }
    else {
        [self disableDeviceButtons];
        _pwnButton.enabled = (bootedDevices.count > 0);
        _tweakStatus.stringValue = @"Simulator not jailbroken";
        _statusImageView.image = [NSImage imageNamed:NSImageNameStatusNone];
    }
}

- (void)refreshDeviceList {
    _statusImageView.image = [NSImage imageNamed:NSImageNameStatusPartiallyAvailable];

    [_devicePopup removeAllItems];

    bootedDevices = [EABootedSimDevice allBootedDevices];
    if (bootedDevices.count > 0) {
        for (EABootedSimDevice *device in bootedDevices) {
            [_devicePopup addItemWithTitle:[NSString stringWithFormat:@"%@ - %@ %@ (%@)", [device name], [device platform], [device runtimeVersion], [device udidString]]];
        }
    }
    else {
        [_devicePopup addItemWithTitle:@"-- None --"];
        [_devicePopup setEnabled:NO];
        [_tweakStatus setStringValue:@"No running simulators"];
    }
    
    [self refreshStatusLabels];
    [_installedTable reloadData];
}

- (void)setupUI {
    _installedTable.delegate = self;
    _installedTable.dataSource = self;
    [self.installedTable reloadData];
    
    _pwnButton.target = self;
    _pwnButton.action = @selector(handleEnableTweaksSelected:);
    
    _removeJailbreakButton.target = self;
    _removeJailbreakButton.action = @selector(handleRemoveJailbreakSelected:);

    [self disableDeviceButtons];
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    NSTableCellView *cellView = [tableView makeViewWithIdentifier:tableColumn.identifier owner:self];
    if ([tableColumn.title isEqualToString:@"Name"]) {
        NSArray *names = @[@"libhooker", @"CarplayEnable", @"loader", @"Apollo", @"libobjsee"];
        cellView.textField.stringValue = names[row];
    }
    else if ([tableColumn.title isEqualToString:@"Type"]) {
        NSArray *types = @[@"iOS Library", @"iOS Tweak", @"Simulator Tweak", @"iOS App", @"iOS Library"];
        cellView.textField.stringValue = types[row];
    }
    else if ([tableColumn.title isEqualToString:@"Location"]) {
        cellView.textField.stringValue = @"/Library/Developer/CoreSimulator/Volumes/iOS_22C150/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS 18.2.simruntime/Contents/Resources/RuntimeRoot/";
    }

    return cellView;
}

- (void)disableDeviceButtons {
    _pwnButton.enabled = NO;
    _removeJailbreakButton.enabled = NO;
    _rebootButton.enabled = NO;
    _respringButton.enabled = NO;
    _installIPAButton.enabled = NO;
    _installTweakButton.enabled = NO;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return showDemoData ? 4 : 0;
}

- (void)handleEnableTweaksSelected:(NSButton *)sender {
    [self disableDeviceButtons];
    _statusImageView.image = [NSImage imageNamed:NSImageNameStatusPartiallyAvailable];
    
    __weak NSButton *weakPwnButton = self.pwnButton;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        
        EABootedSimDevice *device = [self currentDevice];
        if (!device) {
            [self setStatus:@"No active device"];
            return;
        }
        
        [self setStatus:@"Checking for existing overlays"];
        if (![device hasOverlays]) {
            [self setStatus:@"Mounting simruntime overlays"];
            
            if (![device setupMounts]) {
                [self setStatus:@"Failed to setup overlay mounts"];
                weakPwnButton.enabled = YES;
                return;
            }
            
            if (![device hasOverlays]) {
                [self setStatus:@"Failed to locate overlay moint points"];
                weakPwnButton.enabled = YES;
                return;
            }
        }
        
        [self setStatus:@"Checking injection status"];
        if (![device hasInjection]) {
            [self setStatus:@"Setting up tweak injection"];
            [device setupInjection];
            
            if (![device hasInjection]) {
                [self setStatus:@"Failed to setup tweak injection"];
                weakPwnButton.enabled = YES;
                return;
            }
        }

        dispatch_sync(dispatch_get_main_queue(), ^{
            [self refreshDeviceList];
        });
    });
}

- (void)handleRemoveJailbreakSelected:(NSButton *)sender {
    [self disableDeviceButtons];
    _statusImageView.image = [NSImage imageNamed:NSImageNameStatusPartiallyAvailable];
    
    EABootedSimDevice *device = [self currentDevice];
    if (!device) {
        [self setStatus:@"No active device"];
        return;
    }
    
    [device unjailbreak];
    
    [self setStatus:@"Jailbreak removed"];
    [self refreshDeviceList];
}

- (void)setStatus:(NSString *)statusText {
    __weak typeof(self) weakSelf = self;
    void (^updateBlock)(void) = ^(void) {
        weakSelf.tweakStatus.stringValue = statusText;
    };
    
    if ([[NSThread currentThread] isMainThread]) {
        updateBlock();
    }
    else {
        dispatch_sync(dispatch_get_main_queue(), updateBlock);
    }
    
    NSLog(@"%@", statusText);
}

@end
