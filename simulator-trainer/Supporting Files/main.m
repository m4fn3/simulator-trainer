//
//  main.m
//  simulator-trainer
//
//  Created by Ethan Arbuckle on 4/28/25.
//

#import <Cocoa/Cocoa.h>
#import <dlfcn.h>

int main(int argc, const char * argv[]) {
    dlopen("/Library/Developer/PrivateFrameworks/CoreSimulator.framework/Versions/A/CoreSimulator", 0);

    return NSApplicationMain(argc, argv);
}
