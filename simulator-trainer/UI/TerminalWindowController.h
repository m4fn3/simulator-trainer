//
//  TerminalWindowController.h
//  simulator-trainer
//
//  Created by m1book on 5/30/25.
//

@import Cocoa;
@import SwiftTerm;

NS_ASSUME_NONNULL_BEGIN

@interface TerminalWindowController : NSWindowController <NSWindowDelegate, LocalProcessTerminalViewDelegate>

+ (id)presentTerminal;
+ (id)presentTerminalWithExecutable:(NSString *)exe args:(NSArray<NSString *> *)args;

@end

NS_ASSUME_NONNULL_END
