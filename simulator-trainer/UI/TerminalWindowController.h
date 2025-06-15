//
//  TerminalWindowController.h
//  simulator-trainer
//
//  Created by m1book on 5/30/25.
//

@import Cocoa;
#import <SwiftTerm/SwiftTerm-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface TerminalWindowController : NSWindowController <NSWindowDelegate, LocalProcessTerminalViewDelegate>

+ (id)presentTerminal;
+ (id)presentTerminalWithExecutable:(NSString * _Nonnull)exe args:(NSArray<NSString *> * _Nullable)args env:(NSArray * _Nullable)env title:(NSString * _Nullable)title;

@end

NS_ASSUME_NONNULL_END
