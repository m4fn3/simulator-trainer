//
//  DropTargetButton.m
//  simulator-trainer
//
//  Created by m1book on 5/23/25.
//

#import "DropTargetButton.h"

@implementation DropTargetButton

- (instancetype)initWithCoder:(NSCoder *)coder {
    if ((self = [super initWithCoder:coder])) {
        [self commonInit];
    }

    return self;
}

- (id)initWithFrame:(NSRect)frameRect {
    if ((self = [super initWithFrame:frameRect])) {
        [self commonInit];
    }

    return self;
}

- (void)commonInit {
    _acceptedFileExtensions = @[@"deb"];
    [self registerForDraggedTypes:@[NSPasteboardTypeFileURL]];
}

- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender {
    if ([self hasAcceptableFile:sender]) {
        self.highlighted = YES;
        return NSDragOperationCopy;
    }

    return NSDragOperationNone;
}

- (void)draggingExited:(id <NSDraggingInfo>)sender {
    self.highlighted = NO;
}

- (BOOL)prepareForDragOperation:(id <NSDraggingInfo>)sender {
    return [self hasAcceptableFile:sender];
}

- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender {
    self.highlighted = NO;
    NSPasteboard *pboard = [sender draggingPasteboard];
    if ([[pboard types] containsObject:NSPasteboardTypeFileURL]) {
        NSArray *urls = [pboard readObjectsForClasses:@[[NSURL class]] options:nil];
        for (NSURL *url in urls) {
            if ([self.acceptedFileExtensions containsObject:[url.pathExtension lowercaseString]]) {
                if (self.fileDroppedBlock) {
                    self.fileDroppedBlock(url);
                    return YES;
                }
            }
        }
    }

    return NO;
}

- (BOOL)hasAcceptableFile:(id <NSDraggingInfo>)sender {
    NSPasteboard *pboard = [sender draggingPasteboard];
    if ([[pboard types] containsObject:NSPasteboardTypeFileURL]) {
        NSArray *urls = [pboard readObjectsForClasses:@[[NSURL class]] options:nil];
        for (NSURL *url in urls) {
            if ([url isFileURL] && [self.acceptedFileExtensions containsObject:[url.pathExtension lowercaseString]]) {
                return YES;
            }
        }
    }

    return NO;
}

@end
