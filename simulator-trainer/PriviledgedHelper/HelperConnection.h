//
//  HelperConnection.h
//  simulator-trainer
//
//  Created by m1book on 5/22/25.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface HelperConnection : NSObject

- (NSXPCConnection *)getConnection;

@end

NS_ASSUME_NONNULL_END
