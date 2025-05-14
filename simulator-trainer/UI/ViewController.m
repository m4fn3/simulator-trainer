//
//  ViewController.m
//  simulator-trainer
//
//  Created by Ethan Arbuckle on 4/28/25.
//

#import "ViewController.h"
#import "EABootedSimDevice.h"

#define ON_MAIN_THREAD(block) \
    if ([[NSThread currentThread] isMainThread]) { \
        block(); \
    } else { \
        dispatch_sync(dispatch_get_main_queue(), block); \
    }


#import <libobjsee/tracer.h>
#import <dlfcn.h>

void event_handler(const tracer_event_t *event, void *context) {
    // Handle or log the event here
    // You can format it as JSON or colorized text, depending on tracer_format_options_t
    printf("Traced event: class=%s, method=%s\n", event->class_name, event->method_name);
    if (event->formatted_output) {
        printf("%s", event->formatted_output);
    }
}

static tracer_t *tracer = NULL;
static tracer_format_options_t *format = NULL;

void start_tracer(void) {
    tracer_error_t *error = NULL;
    tracer = tracer_create_with_error(&error);
    if (tracer == NULL) {
        if (error != NULL) {
            printf("Error creating tracer: %s\n", error->message);
            free_error(error);
        }

        return;
    }
    
    format = malloc(sizeof(tracer_format_options_t));
    if (format == NULL) {
        printf("Failed to allocate memory for tracer format options\n");
        tracer_cleanup(tracer);
        return;
    }
    
    // set options
    format->include_formatted_trace = true;
    
    
    
//    tracer_format_options_t format = {
//        .include_formatted_trace = true,
//        .include_event_json = true,
//        .output_as_json = true,
//        .include_colors = true,
//        .include_thread_id = true,
//        .args = TRACER_ARG_FORMAT_NONE,
//        .include_indents = true,
//        .include_indent_separators = true,
//        .variable_separator_spacing = false,
//        .static_separator_spacing = 4,
//        .indent_char = ".",
//        .indent_separator_char = "|",
//        .include_newline_in_formatted_trace = true
//    };
//    tracer_set_format_options(tracer, format);
    
//    Dl_info info;
//    if (dladdr((void *)start_tracer, &info) && info.dli_fname) {
//        printf("filtrering to image: %s\n", info.dli_fname);
//        //        tracer_include_image(tracer, info.dli_fname);
//    }
//    
////    tracer_include_class(tracer, "ViewController");
//    
//    tracer_set_output_handler(tracer, event_handler, NULL);
//    //     tracer_set_output_stdout(tracer);
//    
//    if (tracer_start(tracer) != TRACER_SUCCESS) {
//        printf("Failed to start tracer: %s\n", tracer_get_last_error(tracer));
//        tracer_cleanup(tracer);
//        return;
//    }
//    
    printf("tracer started\n");
}
@interface ViewController () {
    NSArray *allSimDevices;
    BOOL showDemoData;
    EASimDevice *selectedDevice;
    NSInteger selectedDeviceIndex;
}

@end

@implementation ViewController

- (instancetype)initWithCoder:(NSCoder *)coder {
    if ((self = [super initWithCoder:coder])) {
        allSimDevices = nil;
        showDemoData = NO;
        selectedDevice = nil;
        selectedDeviceIndex = -1;
    }
    
    start_tracer();

    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    _installedTable.delegate = self;
    _installedTable.dataSource = self;

    _devicePopup.target = self;
    _devicePopup.action = @selector(popupListDidSelectDevice:);
    
    _pwnButton.target = self;
    _pwnButton.action = @selector(handleEnableTweaksSelected:);
    
    _removeJailbreakButton.target = self;
    _removeJailbreakButton.action = @selector(handleRemoveJailbreakSelected:);
    
    _rebootButton.target = self;
    _rebootButton.action = @selector(handleRebootSelected:);
    
    _respringButton.target = self;
    _respringButton.action = @selector(handleRespringSelected:);
    
    _bootButton.target = self;
    _bootButton.action = @selector(handleBootSelected:);
    
    [self _populateDevicePopup];
    [self refreshDeviceList];
}

- (EASimDevice *)currentDevice {
    if (allSimDevices.count == 0) {
        return nil;
    }
    
    NSInteger selectedIndex = [_devicePopup indexOfSelectedItem];
    if (selectedIndex >= allSimDevices.count) {
        return nil;
    }
    
    EASimDevice *device = allSimDevices[selectedIndex];
    _bootButton.enabled = !device.isBooted;
    
    return device;
}

- (void)refreshDeviceList {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // Reload the list of devices
        BOOL isFirstFetch = (self->allSimDevices == nil);
        self->allSimDevices = [EABootedSimDevice allDevices];
        
        ON_MAIN_THREAD(^{
            // Update the device list UI whenever the list changes
            [self _populateDevicePopup];
            
            if (isFirstFetch) {
                [self _autoselectDevice];
            }
        });
    });
}

- (void)_populateDevicePopup {    
    // Populate the device popup list with available devices
    NSArray *deviceList = self->allSimDevices;
    [_devicePopup removeAllItems];
    if (deviceList.count == 0) {
        [_devicePopup addItemWithTitle:@"-- None --"];
        [_devicePopup selectItemAtIndex:0];
        [_devicePopup setEnabled:NO];
        return;
    }
    
    for (EASimDevice *device in deviceList) {
        [_devicePopup addItemWithTitle:[device displayString]];
    }
    
    if (self->selectedDevice) {
        NSInteger index = [deviceList indexOfObject:self->selectedDevice];
        if (index != NSNotFound) {
            [_devicePopup selectItemAtIndex:index];
        }
    }
    else {
        NSLog(@"No device selected -- defaulting to first device");
//        [_devicePopup selectItemAtIndex:0];
    }

    [_devicePopup setEnabled:YES];
}

- (void)_autoselectDevice {
    NSInteger selectedDeviceIndex = 0;
    // Default selection to the first jailbroken booted device, falling
    // back to the first booted device if none are jailbroken, then
    // finally the first iOS-platform simulator if none are booted
    for (int i = 0; i < allSimDevices.count; i++) {
        EASimDevice *device = allSimDevices[i];
        if (device.isBooted && [(EABootedSimDevice *)device hasInjection]) {
            selectedDeviceIndex = i;
            break;
        }
        else if (device.isBooted) {
            selectedDeviceIndex = i;
            break;
        }
        else if ([device.platform isEqualToString:@"iOS"]) {
            selectedDeviceIndex = i;
            break;
        }
    }
    
    NSLog(@"Autoselecting device at index %ld", (long)selectedDeviceIndex);
    [_devicePopup selectItemAtIndex:selectedDeviceIndex];
    [self popupListDidSelectDevice:_devicePopup];
}

- (void)_updateSelectedDeviceUI {
    // Update the device buttons and labels based on the selected device
    if (!self->selectedDevice) {
        // No device selected -- disable buttons
        [self disableDeviceButtons];
        return;
    }
    
    // Start with everything disabled
    [self disableDeviceButtons];
    showDemoData = NO;

    _statusImageView.image = [NSImage imageNamed:NSImageNameStatusUnavailable];
    _tweakStatus.stringValue = @"No active device";
    
    if (self->selectedDevice.isBooted) {
        // Booted device: enable reboot and check for jailbreak
        _rebootButton.enabled = YES;
        
        EABootedSimDevice *bootedSim = [EABootedSimDevice fromSimDevice:self->selectedDevice];
        if ([bootedSim isJailbroken]) {
            // Device is jailbroken
            _removeJailbreakButton.enabled = YES;
            _respringButton.enabled = YES;
            _installIPAButton.enabled = YES;
            _installTweakButton.enabled = YES;
            _statusImageView.image = [NSImage imageNamed:NSImageNameStatusAvailable];
            _tweakStatus.stringValue = @"Injection active";
            
            showDemoData = YES;
        }
        else {
            // Device is not jailbroken
            _pwnButton.enabled = YES;
            _installIPAButton.enabled = YES;
            _statusImageView.image = [NSImage imageNamed:NSImageNameStatusPartiallyAvailable];
            _tweakStatus.stringValue = @"Simulator not jailbroken";
        }
    }
    else {
        // Device is not booted: enable boot button
        _bootButton.enabled = YES;
        _rebootButton.enabled = NO;
    }
    
    [_installedTable reloadData];
}

- (void)popupListDidSelectDevice:(NSPopUpButton *)sender {
    if (self->selectedDevice && self->selectedDevice.delegate) {
        self->selectedDevice.delegate = nil;
    }

    if (self->allSimDevices.count == 0) {
        return;
    }
    
    NSInteger selectedIndex = [_devicePopup indexOfSelectedItem];
    if (selectedIndex == -1 || selectedIndex >= self->allSimDevices.count) {
        NSLog(@"Invalid device index selected");
        return;
    }
    
    EASimDevice *device = self->allSimDevices[selectedIndex];
    if (device.isBooted) {
        self->selectedDevice = [EABootedSimDevice fromSimDevice:device];
    }
    else {
        self->selectedDevice = device;
    }

    self->selectedDevice.delegate = self;
    NSLog(@"Selected device: %@", self->selectedDevice);
    
    self->selectedDeviceIndex = selectedIndex;
    [self->selectedDevice reloadDeviceState];
    [self _updateSelectedDeviceUI];
}

- (void)handleRebootSelected:(NSButton *)sender {
    if (!self->selectedDevice) {
        [self setStatus:@"No active device"];
        return;
    }
    
    NSLog(@"Rebooting device: %@", self->selectedDevice);
    if (self->selectedDevice.isBooted) {
        [(EABootedSimDevice *)self->selectedDevice reboot];
    }
    else {
        [self->selectedDevice boot];
    }
}

- (void)handleBootSelected:(NSButton *)sender {
    if (!self->selectedDevice) {
        [self setStatus:@"No active device"];
        return;
    }
    
    [self->selectedDevice boot];
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    NSTableCellView *cellView = [tableView makeViewWithIdentifier:tableColumn.identifier owner:self];
    if ([tableColumn.title isEqualToString:@"Name"]) {
        NSArray *names = @[@"libhooker", @"CydiaSubstrate", @"simbins", @"tweakloader", @"Apollo", @"libobjsee"];
        cellView.textField.stringValue = names[row];
    }
    else if ([tableColumn.title isEqualToString:@"Location"]) {
        if (self->selectedDevice) {
            cellView.textField.stringValue = [self->selectedDevice runtimeRoot];
        }
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
    _bootButton.enabled = NO;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return showDemoData ? 6 : 0;
}

- (void)handleEnableTweaksSelected:(NSButton *)sender {
    [self disableDeviceButtons];
    _statusImageView.image = [NSImage imageNamed:NSImageNameStatusPartiallyAvailable];
    EABootedSimDevice *device = (EABootedSimDevice *)self->selectedDevice;
    if (!device || ![device isKindOfClass:[EABootedSimDevice class]]) {
        [self setStatus:@"No active device"];
        return;
    }

    __weak NSButton *weakPwnButton = self.pwnButton;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        
        if (!device) {
            [self setStatus:@"No active device"];
            return;
        }
        
        [self setStatus:@"Checking for existing overlays"];
        if (![device hasOverlays]) {
            [self setStatus:@"Mounting simruntime overlays"];
            
            if (![device prepareJbFilesystem]) {
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
    
    if (!self->selectedDevice) {
        [self setStatus:@"No active device"];
        return;
    }
    
    [(EABootedSimDevice *)self->selectedDevice unjailbreak];
    
    [self setStatus:@"Jailbreak removed"];
    [self refreshDeviceList];
}

- (void)handleRespringSelected:(NSButton *)sender {
    NSLog(@"Respring selected");
}

- (void)setStatus:(NSString *)statusText {
    __weak typeof(self) weakSelf = self;
    ON_MAIN_THREAD(^{
        weakSelf.tweakStatus.stringValue = statusText;
    });
}

- (void)deviceDidBoot:(EASimDevice *)simDevice {
    NSLog(@"Device did boot: %@", simDevice);
    
    NSInteger indexOfDevice = [self->allSimDevices indexOfObject:simDevice];
    if (indexOfDevice == NSNotFound) {
        NSLog(@"Device not found in list: %@", simDevice);
        return;
    }
    
    if (self->selectedDevice) {
        self->selectedDevice.delegate = nil;
    }
    
    self->selectedDevice = simDevice;
    self->selectedDevice.delegate = self;
    
    __weak typeof(self) weakSelf = self;
    ON_MAIN_THREAD(^{
        [weakSelf.devicePopup selectItemAtIndex:indexOfDevice];
        [self refreshDeviceList];
        [self _updateSelectedDeviceUI];
        weakSelf.bootButton.enabled = NO;
        weakSelf.rebootButton.enabled = YES;
    });
}

- (void)deviceDidReboot:(EASimDevice *)simDevice {
    NSLog(@"Device did reboot: %@", simDevice);
    ON_MAIN_THREAD(^{
        self.bootButton.enabled = NO;
        self.rebootButton.enabled = YES;
    });
}

- (void)deviceDidShutdown:(EASimDevice *)simDevice {
    NSLog(@"Device did shutdown: %@", simDevice);
    ON_MAIN_THREAD(^{
        self.bootButton.enabled = YES;
        self.rebootButton.enabled = NO;
        self.removeJailbreakButton.enabled = NO;
        self.respringButton.enabled = NO;
        self.installIPAButton.enabled = NO;
        self.installTweakButton.enabled = NO;
    });
}

- (void)device:(EASimDevice *)simDevice didFailToBootWithError:(NSError *)error {
    NSLog(@"Device failed to boot: %@", error);
}

@end
