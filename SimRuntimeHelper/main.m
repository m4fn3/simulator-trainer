//
//  main.m
//  SimRuntimeHelper
//
//  Created by Ethan Arbuckle on 5/17/25.
//

#import <Foundation/Foundation.h>
#import "SimHelperCommon.h"

@interface SimRuntimeHelper : NSObject <NSXPCListenerDelegate, SimRuntimeHelperProtocol>
@property (atomic, strong) NSXPCListener *listener;
- (void)startListener;
@end

@implementation SimRuntimeHelper

- (id)init {
    if ((self = [super init])) {
        self.listener = [[NSXPCListener alloc] initWithMachServiceName:kSimRuntimeHelperServiceName];
        self.listener.delegate = self;
    }
    
    return self;
}

- (void)startListener {
    [self.listener resume];
    [[NSRunLoop currentRunLoop] run];
}

- (BOOL)listener:(NSXPCListener *)listener shouldAcceptNewConnection:(NSXPCConnection *)newConnection {
    newConnection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SimRuntimeHelperProtocol)];
    newConnection.exportedObject = self;
    [newConnection resume];
    return YES;
}

- (NSError *)checkClientAuthorizationData:(NSData *)authorizationData {
    NSError *error = nil;
    if (!authorizationData || authorizationData.length != sizeof(AuthorizationExternalForm)) {
        error = [NSError errorWithDomain:NSOSStatusErrorDomain code:paramErr userInfo:@{NSLocalizedDescriptionKey: @"Invalid authorization data"}];
        return error;
    }
    
    AuthorizationRef authRef = NULL;
    OSStatus ret = AuthorizationCreateFromExternalForm((AuthorizationExternalForm *)authorizationData.bytes, &authRef);
    if (ret == errAuthorizationSuccess) {
        AuthorizationItem authItems[] = {{kAuthorizationRightExecute, 0, NULL, 0}};
        AuthorizationRights rights = {1, authItems};
        
        uint32_t flags = kAuthorizationFlagDefaults | kAuthorizationFlagInteractionAllowed | kAuthorizationFlagExtendRights;
        ret = AuthorizationCopyRights(authRef, &rights, kAuthorizationEmptyEnvironment, flags, NULL);
    }
    
    if (ret != errAuthorizationSuccess) {
        error = [NSError errorWithDomain:NSOSStatusErrorDomain code:ret userInfo:@{NSLocalizedDescriptionKey: @"Authorization failed"}];
    }
    
    if (authRef) {
        if (AuthorizationFree(authRef, kAuthorizationFlagDefaults) != errAuthorizationSuccess) {
            NSLog(@"Failed to free authorization reference. leaking");
        }
    }
    
    return error;
}

- (void)setupTweakInjectionWithOptions:(SimInjectionOptions *)options completion:(void (^)(NSError *error))completion {
    [SimHelperCommon installTweakLoaderWithOptions:options completion:completion];
}

- (void)mountTmpfsOverlaysAtPaths:(NSArray<NSString *> *)overlayPaths completion:(void (^)(NSError *error))completion {
    for (NSString *overlayPath in overlayPaths) {
        NSError *outterError = nil;
        if (![SimHelperCommon mountOverlayAtPath:overlayPath error:&outterError]) {
            NSLog(@"Failed to mount overlay at path: %@ with error: %@", overlayPath, outterError);
            completion(outterError);
            return;
        }
    }
    
    completion(nil);
}

- (void)unmountMountPoints:(NSArray <NSString *> *)mountPoints completion:(void (^)(NSError *))completion {
    for (NSString *mountPoint in mountPoints) {
        NSError *error = nil;
        if (![SimHelperCommon unmountOverlayAtPath:mountPoint error:&error]) {
            completion(error);
            return;
        }
    }
    
    completion(nil);
}

@end


int main(int argc, const char * argv[]) {
    @autoreleasepool {

        SimRuntimeHelper *helper = [[SimRuntimeHelper alloc] init];
        [helper startListener];
    }

    return 0;
}
