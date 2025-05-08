//
//  ViewController.h
//  simulator-trainer
//
//  Created by Ethan Arbuckle on 4/28/25.
//

#import <Cocoa/Cocoa.h>

@interface ViewController : NSViewController <NSTableViewDelegate, NSTableViewDataSource>

@property (nonatomic, weak) IBOutlet NSPopUpButton *devicePopup;
@property (nonatomic, weak) IBOutlet NSImageView *statusImageView;
@property (nonatomic, weak) IBOutlet NSTextField *tweakStatus;
@property (nonatomic, weak) IBOutlet NSTableView *installedTable;
@property (nonatomic, weak) IBOutlet NSButton *respringButton;
@property (nonatomic, weak) IBOutlet NSButton *rebootButton;
@property (nonatomic, weak) IBOutlet NSButton *pwnButton;
@property (nonatomic, weak) IBOutlet NSButton *removeJailbreakButton;
@property (nonatomic, weak) IBOutlet NSButton *installTweakButton;
@property (nonatomic, weak) IBOutlet NSButton *installIPAButton;
@property (nonatomic, weak) IBOutlet NSButton *bootButton;

@end

