//
//  HelperConnection.m
//  simulator-trainer
//
//  Created by m1book on 5/22/25.
//

#import <ServiceManagement/ServiceManagement.h>
#import "HelperConnection.h"
#import "SimHelperCommon.h"

@interface HelperConnection () {
    AuthorizationRef authRef;
}

@property (atomic, strong) NSXPCConnection *helperConnection;
@property (atomic, copy) NSData *authorizationData;

@end

@implementation HelperConnection

- (id)init {
    if ((self = [super init])) {
        self.helperConnection = nil;
        self.authorizationData = nil;
    }
    
    return self;
}

- (void)_setupAuthorizationForHelper {
    // Create an authorization reference to use for the helper
    if (AuthorizationCreate(NULL, NULL, 0, &self->authRef) == errAuthorizationSuccess) {
        AuthorizationExternalForm extForm;
        if (AuthorizationMakeExternalForm(self->authRef, &extForm) == errAuthorizationSuccess) {
            self.authorizationData = [NSData dataWithBytes:&extForm length:sizeof(extForm)];
        }
    }
    
    // And then grant the authorization rights to the helper
    if (self->authRef) {
        [SimHelperCommon grantAuthorizationRights:self->authRef];
    }
}

- (BOOL)_installHelperService {
    // Check if the helper service is already installed
    CFErrorRef error = NULL;
    CFDictionaryRef jobDictionary = SMJobCopyDictionary(kSMDomainSystemLaunchd, (CFStringRef)kSimRuntimeHelperServiceName);
    if (jobDictionary) {
        // Nothing further to do
        CFRelease(jobDictionary);
//        return YES;
    }
    
    // The helper service is not installed, so install it
    if (SMJobBless(kSMDomainSystemLaunchd, (CFStringRef)kSimRuntimeHelperServiceName, self->authRef, &error)) {
        return YES;
    }
    
    if (error) {
        NSLog(@"Failed to install helper service: %@", (__bridge NSError *)error);
        CFRelease(error);
    }
    
    return NO;
}

- (void)connectToHelperService {
    if (self.helperConnection) {
        // Already connected
        return;
    }
    
    // Check if the authorization reference is valid. Try to create one if not
    if (!self->authRef) {
        [self _setupAuthorizationForHelper];
        
        // If that failed, the connection cannot proceed
        if (!self->authRef) {
            NSLog(@"Failed to create authorization reference, cannot connect to helper");
            return;
        }
    }
    
    // Install the helper service if needed
    if (![self _installHelperService]) {
        NSLog(@"Connection to helper cannot be established, helper service failed to install");
        return;
    }
    
    self.helperConnection = [[NSXPCConnection alloc] initWithMachServiceName:(NSString *)kSimRuntimeHelperServiceName options:NSXPCConnectionPrivileged];
    self.helperConnection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SimRuntimeHelperProtocol)];
    self.helperConnection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SimRuntimeHelperProtocol)];
    self.helperConnection.exportedObject = self;
    
    __weak typeof(self) weakSelf = self;
    self.helperConnection.invalidationHandler = ^{
        weakSelf.helperConnection.invalidationHandler = nil;
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            weakSelf.helperConnection = nil;
            NSLog(@"Connection to helper service invalidated");
        }];
    };
    
    [self.helperConnection resume];
}

- (NSXPCConnection *)getConnection {
    if (!self.helperConnection) {
        [self connectToHelperService];
    }
    
    return self.helperConnection;
}

@end
