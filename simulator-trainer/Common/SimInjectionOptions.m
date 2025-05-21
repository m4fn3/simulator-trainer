//
//  SimInjectionOptions.m
//  simulator-trainer
//
//  Created by m1book on 5/18/25.
//

#import "SimInjectionOptions.h"

@implementation SimInjectionOptions

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.tweakLoaderSourcePath forKey:@"tweakLoaderSourcePath"];
    [coder encodeObject:self.tweakLoaderDestinationPath forKey:@"tweakLoaderDestinationPath"];
    [coder encodeObject:self.victimPathForTweakLoader forKey:@"victimPathForTweakLoader"];
    [coder encodeObject:self.optoolPath forKey:@"optoolPath"];
    [coder encodeObject:self.filesToCopy forKey:@"filesToCopy"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    if ((self = [super init])) {
        _tweakLoaderSourcePath = [coder decodeObjectOfClass:[NSString class] forKey:@"tweakLoaderSourcePath"];
        _tweakLoaderDestinationPath = [coder decodeObjectOfClass:[NSString class] forKey:@"tweakLoaderDestinationPath"];
        _victimPathForTweakLoader = [coder decodeObjectOfClass:[NSString class] forKey:@"victimPathForTweakLoader"];
        _optoolPath = [coder decodeObjectOfClass:[NSString class] forKey:@"optoolPath"];
        NSSet *allowedClasses = [NSSet setWithObjects:[NSDictionary class], [NSString class], [NSString class], nil];
        _filesToCopy = [coder decodeObjectOfClasses:allowedClasses forKey:@"filesToCopy"];
    }

    return self;
}

@end
