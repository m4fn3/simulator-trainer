//
//  TerminalWindowController.m
//  simulator-trainer
//
//  Created by m1book on 5/30/25.
//

#import "TerminalWindowController.h"
@import SwiftTerm;

@interface TerminalWindowController ()
@property (nonatomic, strong) LocalProcessTerminalView *terminalView;
@end

@implementation TerminalWindowController

+ (id)presentTerminal {
    return [self presentTerminalWithExecutable:@"/bin/bash" args:@[] env:nil title:nil];
}

+ (id)presentTerminalWithExecutable:(NSString *)exe args:(NSArray<NSString *> *)args env:(NSArray *)env title:(NSString *)title {
    TerminalWindowController *controller = [[self alloc] initWithExecutable:exe args:args env:env title:title];
    [controller showWindow:nil];
    return controller;
}

- (instancetype)initWithExecutable:(NSString *)exe args:(NSArray<NSString *> *)args env:(NSArray *)env title:(NSString *)title {
    NSRect initialFrame = NSMakeRect(0, 0, 800, 500);
    NSWindow *termWindow = [[NSWindow alloc] initWithContentRect:initialFrame styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable | NSWindowStyleMaskMiniaturizable) backing:NSBackingStoreBuffered defer:NO];
    
    if ((self = [super initWithWindow:termWindow])) {
        termWindow.title = title ?: @"Terminal";
        termWindow.delegate = self;
        termWindow.releasedWhenClosed = NO;
        termWindow.minSize = NSMakeSize(480, 240);

        _terminalView = [[LocalProcessTerminalView alloc] initWithFrame:initialFrame];
        _terminalView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        _terminalView.processDelegate = self;
        _terminalView.font = [NSFont monospacedSystemFontOfSize:10 weight:NSFontWeightRegular];
        [termWindow setContentView:_terminalView];
        
         [_terminalView startProcessWithExecutable:exe args:args environment:env execName:nil];
    }

    return self;
}

- (void)windowWillClose:(NSNotification *)note {
    if (self.terminalView.process.running) {
        kill(self.terminalView.process.running, SIGTERM);
    }

    self.terminalView.processDelegate = nil;
    self.terminalView = nil;
}

- (void)sizeChangedWithSource:(LocalProcessTerminalView *)source newCols:(NSInteger)newCols newRows:(NSInteger)newRows {
    NSLog(@"Terminal size changed: %ld cols, %ld rows", (long)newCols, (long)newRows);
}

- (void)setTerminalTitleWithSource:(LocalProcessTerminalView *)source title:(NSString *)title {
    self.window.title = title.length ? title : @"Terminal";
}

- (void)hostCurrentDirectoryUpdateWithSource:(TerminalView *)source directory:(NSString *)directory {
    self.window.subtitle = directory ?: @"";
}

- (void)processTerminatedWithSource:(TerminalView *)source exitCode:(int32_t)exitCode {
    NSString *msg = [NSString stringWithFormat:@"Process exited %d", exitCode];
    self.window.title = msg;
}

@end
