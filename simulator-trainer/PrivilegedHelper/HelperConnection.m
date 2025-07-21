//
//  HelperConnection.m
//  simulator-trainer
//
//  Created by m1book on 5/22/25.
//

#import <ServiceManagement/ServiceManagement.h>
#import "SimRuntimeHelperProtocol.h"
#import "HelperConnection.h"

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
        if (AuthorizationRightGet(kSimRuntimeHelperAuthRightName.UTF8String, NULL) == errAuthorizationDenied) {
            // If the right doesn't exist, create it with the default rule
            CFTypeRef rule = (__bridge CFTypeRef)kSimRuntimeHelperAuthRightDefaultRule;
            CFStringRef description = (__bridge CFStringRef)kSimRuntimeHelperAuthRightDescription;
            
            if (AuthorizationRightSet(self->authRef, kSimRuntimeHelperAuthRightName.UTF8String, rule, description, NULL, NULL) != errAuthorizationSuccess) {
                // Failed to set the right. Auth failure
                NSLog(@"Failed to set authorization right");
                self->authRef = NULL;
            }
        }
    }
}

- (BOOL)_installHelperService {
    // Check if the helper service is already installed
    CFErrorRef error = NULL;
    CFDictionaryRef jobDictionary = SMJobCopyDictionary(kSMDomainSystemLaunchd, (CFStringRef)kSimRuntimeHelperServiceName);
    if (jobDictionary) {
        // Nothing further to do
        CFRelease(jobDictionary);
        return YES;
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

- (void)mountTmpfsOverlaysAtPaths:(NSArray<NSString *> *)overlayPaths completion:(void (^)(NSError * _Nullable error))completion {
    NSXPCConnection *conn = [self getConnection];
    if (!conn) {
        if (completion) {
            completion([NSError errorWithDomain:NSCocoaErrorDomain code:-1 userInfo:@{NSLocalizedDescriptionKey: @"XPC connection not available."}]);
        }

        return;
    }

    // Ensure we have valid authorization
    if (!self->authRef) {
        [self _setupAuthorizationForHelper];
        if (!self->authRef) {
            if (completion) {
                completion([NSError errorWithDomain:NSCocoaErrorDomain code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Failed to create authorization reference."}]);
            }
            return;
        }
    }

    // Acquire the right
    AuthorizationItem right = {kSimRuntimeHelperAuthRightName.UTF8String, 0, NULL, 0};
    AuthorizationRights rights = {1, &right};
    AuthorizationFlags flags = kAuthorizationFlagExtendRights | kAuthorizationFlagInteractionAllowed;

    OSStatus status = AuthorizationCopyRights(self->authRef, &rights, NULL, flags, NULL);
    if (status != errAuthorizationSuccess) {
        NSLog(@"Failed to acquire authorization rights: %d", (int)status);
        if (completion) {
            completion([NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:@{NSLocalizedDescriptionKey: @"Failed to acquire authorization rights."}]);
        }
        return;
    }

    // Create fresh external form
    AuthorizationExternalForm extForm;
    if (AuthorizationMakeExternalForm(self->authRef, &extForm) != errAuthorizationSuccess) {
        if (completion) {
            completion([NSError errorWithDomain:NSCocoaErrorDomain code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Failed to create external authorization form."}]);
        }
        return;
    }

    self.authorizationData = [NSData dataWithBytes:&extForm length:sizeof(extForm)];

    id <SimRuntimeHelperProtocol> proxy = [conn remoteObjectProxyWithErrorHandler:^(NSError * _Nonnull proxyError) {
        NSLog(@"XPC proxy error (mountTmpfsOverlaysAtPaths): %@", proxyError);
        if (completion) {
            completion(proxyError);
        }
    }];
    
    [proxy mountTmpfsOverlaysAtPaths:overlayPaths withAuthorization:self.authorizationData completion:completion];
}

- (void)setupTweakInjectionWithOptions:(SimInjectionOptions *)options completion:(void (^)(NSError * _Nullable error))completion {
    NSXPCConnection *conn = [self getConnection];
    if (!conn) {
        if (completion) {
            completion([NSError errorWithDomain:NSCocoaErrorDomain code:-1 userInfo:@{NSLocalizedDescriptionKey: @"XPC connection not available."}]);
        }

        return;
    }

    // Ensure we have valid authorization
    if (!self->authRef) {
        [self _setupAuthorizationForHelper];
        if (!self->authRef) {
            if (completion) {
                completion([NSError errorWithDomain:NSCocoaErrorDomain code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Failed to create authorization reference."}]);
            }
            return;
        }
    }

    // Acquire the right
    AuthorizationItem right = {kSimRuntimeHelperAuthRightName.UTF8String, 0, NULL, 0};
    AuthorizationRights rights = {1, &right};
    AuthorizationFlags flags = kAuthorizationFlagExtendRights | kAuthorizationFlagInteractionAllowed;

    OSStatus status = AuthorizationCopyRights(self->authRef, &rights, NULL, flags, NULL);
    if (status != errAuthorizationSuccess) {
        NSLog(@"Failed to acquire authorization rights: %d", (int)status);
        if (completion) {
            completion([NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:@{NSLocalizedDescriptionKey: @"Failed to acquire authorization rights."}]);
        }
        return;
    }

    // Create fresh external form
    AuthorizationExternalForm extForm;
    if (AuthorizationMakeExternalForm(self->authRef, &extForm) != errAuthorizationSuccess) {
        if (completion) {
            completion([NSError errorWithDomain:NSCocoaErrorDomain code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Failed to create external authorization form."}]);
        }
        return;
    }

    self.authorizationData = [NSData dataWithBytes:&extForm length:sizeof(extForm)];

    id <SimRuntimeHelperProtocol> proxy = [conn remoteObjectProxyWithErrorHandler:^(NSError * _Nonnull proxyError) {
        NSLog(@"XPC proxy error (setupTweakInjectionWithOptions): %@", proxyError);
        if (completion) {
            completion(proxyError);
        }
    }];
    
    [proxy setupTweakInjectionWithOptions:options withAuthorization:self.authorizationData completion:completion];
}

- (void)unmountMountPoints:(NSArray<NSString *> *)mountPoints completion:(void (^)(NSError * _Nullable error))completion {
    NSXPCConnection *conn = [self getConnection];
    if (!conn) {
        if (completion) {
            completion([NSError errorWithDomain:NSCocoaErrorDomain code:-1 userInfo:@{NSLocalizedDescriptionKey: @"XPC connection not available."}]);
        }

        return;
    }

    // Ensure we have valid authorization
    if (!self->authRef) {
        [self _setupAuthorizationForHelper];
        if (!self->authRef) {
            if (completion) {
                completion([NSError errorWithDomain:NSCocoaErrorDomain code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Failed to create authorization reference."}]);
            }
            return;
        }
    }

    // Acquire the right
    AuthorizationItem right = {kSimRuntimeHelperAuthRightName.UTF8String, 0, NULL, 0};
    AuthorizationRights rights = {1, &right};
    AuthorizationFlags flags = kAuthorizationFlagExtendRights | kAuthorizationFlagInteractionAllowed;

    OSStatus status = AuthorizationCopyRights(self->authRef, &rights, NULL, flags, NULL);
    if (status != errAuthorizationSuccess) {
        NSLog(@"Failed to acquire authorization rights: %d", (int)status);
        if (completion) {
            completion([NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:@{NSLocalizedDescriptionKey: @"Failed to acquire authorization rights."}]);
        }
        return;
    }

    // Create fresh external form
    AuthorizationExternalForm extForm;
    if (AuthorizationMakeExternalForm(self->authRef, &extForm) != errAuthorizationSuccess) {
        if (completion) {
            completion([NSError errorWithDomain:NSCocoaErrorDomain code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Failed to create external authorization form."}]);
        }
        return;
    }

    self.authorizationData = [NSData dataWithBytes:&extForm length:sizeof(extForm)];

    id <SimRuntimeHelperProtocol> proxy = [conn remoteObjectProxyWithErrorHandler:^(NSError * _Nonnull proxyError) {
        NSLog(@"XPC proxy error (unmountMountPoints): %@", proxyError);
        if (completion) {
            completion(proxyError);
        }
    }];

    [proxy unmountMountPoints:mountPoints withAuthorization:self.authorizationData completion:completion];
}

@end
