#import <Foundation/Foundation.h>

@class NEPacketTunnelFlow;
@class NEPacketTunnelNetworkSettings;

NS_ASSUME_NONNULL_BEGIN

typedef void (^OpenVPNRunnerLogHandler)(NSString *message);
typedef void (^OpenVPNNetworkSettingsHandler)(NEPacketTunnelNetworkSettings *settings);

@interface OpenVPNRunnerBridge : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)new NS_UNAVAILABLE;

- (instancetype)initWithLogHandler:(OpenVPNRunnerLogHandler)logHandler NS_DESIGNATED_INITIALIZER;

/// Must be set before `start` so TunBuilder can return a valid file descriptor (NEPacketTunnelFlow is not a real utun).
- (void)setPacketFlow:(NEPacketTunnelFlow *)packetFlow;

/// Hostname of the WSS proxy (same as provider `host`). Resolved to IPv4 /32 excluded routes so the transport does not loop through the tunnel.
- (void)setWssProxyHostnameForExclusion:(NSString *)hostname;

/// Called on the main queue after OpenVPN PUSH options are applied so the system routes public traffic through the tunnel (replaces placeholder settings).
- (void)setNetworkSettingsUpdateHandler:(nullable OpenVPNNetworkSettingsHandler)handler;

/// IP packets from `NEPacketTunnelFlow.readPackets` (no link header). Protocols: `AF_INET` / `AF_INET6`.
- (void)injectDataPacketsFromTunnel:(NSArray<NSData *> *)packets protocols:(NSArray<NSNumber *> *)protocols;

- (BOOL)prepareWithOvpnContent:(NSString *)ovpnContent error:(NSError * _Nullable * _Nullable)error;
- (void)start;
- (void)stop;

@end

NS_ASSUME_NONNULL_END
