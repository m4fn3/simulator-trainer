//
//  ViewController.h
//  simulator-trainer
//
//  Created by Ethan Arbuckle on 4/28/25.
//

#import <Cocoa/Cocoa.h>
#import "SimulatorWrapper.h"
#import "DropTargetButton.h"
#import "PackageInstallationService.h"

@interface ViewController : NSViewController <SimulatorWrapperDelegate>

@property (nonatomic, strong) PackageInstallationService *packageService;

@property (nonatomic, weak) IBOutlet NSPopUpButton *devicePopup;
@property (nonatomic, weak) IBOutlet NSImageView *statusImageView;
@property (nonatomic, weak) IBOutlet NSTextField *tweakStatus;
@property (nonatomic, weak) IBOutlet NSButton *respringButton;
@property (nonatomic, weak) IBOutlet NSButton *rebootButton;
@property (nonatomic, weak) IBOutlet NSButton *jailbreakButton;
@property (nonatomic, weak) IBOutlet NSButton *removeJailbreakButton;
@property (nonatomic, weak) IBOutlet DropTargetButton *installTweakButton;
@property (nonatomic, weak) IBOutlet NSButton *installIPAButton;
@property (nonatomic, weak) IBOutlet NSButton *bootButton;
@property (nonatomic, weak) IBOutlet NSButton *shutdownButton;
@property (nonatomic, weak) IBOutlet NSButton *openTweakFolderButton;


@end

