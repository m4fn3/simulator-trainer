//
//  DropTargetButton.h
//  simulator-trainer
//
//  Created by m1book on 5/23/25.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface DropTargetButton : NSButton

@property (nonatomic, copy, nullable) void (^fileDroppedBlock)(NSURL *fileURL);
@property (nonatomic, strong) NSArray<NSString *> *acceptedFileExtensions;

@end

NS_ASSUME_NONNULL_END
