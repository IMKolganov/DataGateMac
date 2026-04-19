#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^OpenVPNRunnerLogHandler)(NSString *message);

@interface OpenVPNRunnerBridge : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)new NS_UNAVAILABLE;

- (instancetype)initWithLogHandler:(OpenVPNRunnerLogHandler)logHandler NS_DESIGNATED_INITIALIZER;

- (BOOL)prepareWithOvpnContent:(NSString *)ovpnContent error:(NSError * _Nullable * _Nullable)error;
- (void)start;
- (void)stop;

@end

NS_ASSUME_NONNULL_END
