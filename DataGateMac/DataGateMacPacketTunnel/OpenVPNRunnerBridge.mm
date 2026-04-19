#import "OpenVPNRunnerBridge.h"

#import <NetworkExtension/NetworkExtension.h>
#import <arpa/inet.h>
#import <errno.h>
#import <fcntl.h>
#import <netdb.h>
#import <netinet/in.h>
#import <poll.h>
#import <sys/socket.h>
#import <unistd.h>

#import <CoreFoundation/CoreFoundation.h>

#include <atomic>
#include <memory>
#include <string>
#include <thread>

#include "ovpncli.hpp"

@interface OpenVPNRunnerBridge ()
@property (nonatomic, copy) OpenVPNRunnerLogHandler logHandler;
- (int)openvpnTunEstablishSocketPair;
- (void)openvpnTunTeardown;
- (void)tunRelayRecvLoop;
- (void)openvpnTunBuilderReset;
- (void)openvpnTunBuilderAddIpv4Address:(NSString *)address prefixLength:(int)prefixLength gateway:(NSString *)gateway;
- (void)openvpnTunBuilderSetRerouteGwIpv4:(BOOL)ipv4 ipv6:(BOOL)ipv6 flags:(unsigned int)flags;
- (void)openvpnTunBuilderAppendExcludedIpv4:(NSString *)destination prefixLength:(int)prefixLength;
- (void)openvpnTunBuilderReplaceDnsIpv4Servers:(NSArray<NSString *> *)servers;
- (void)openvpnTunBuilderSetMtuValue:(int)mtu;
- (void)applyConsolidatedNetworkSettingsIfNeeded;
- (BOOL)allowSocketPressureLog;
@end

namespace {

static NSString *ToNSString(const std::string &value) {
    return [NSString stringWithUTF8String:value.c_str()] ?: @"";
}

static NSString *OpenVPNSubnetMaskStringForPrefixLength(int prefixLength) {
    if (prefixLength <= 0 || prefixLength > 32) {
        return @"255.255.255.255";
    }
    const uint32_t plen = (uint32_t)prefixLength;
    const uint32_t mask = plen >= 32 ? 0xFFFFFFFFu : (0xFFFFFFFFu << (32u - plen));
    struct in_addr a;
    a.s_addr = htonl(mask);
    char buf[INET_ADDRSTRLEN];
    if (inet_ntop(AF_INET, &a, buf, sizeof(buf)) == nullptr) {
        return @"255.255.255.0";
    }
    return [NSString stringWithUTF8String:buf];
}

static bool OpenVPNDatagramSendWithPollWait(int fd, const void *buffer, size_t length) {
    const int maxWaitCycles = 600;
    for (int cycle = 0; cycle < maxWaitCycles; cycle++) {
        const ssize_t w = send(fd, buffer, length, 0);
        if (w == (ssize_t)length) {
            return true;
        }
        if (w < 0) {
            if (errno == EINTR) {
                continue;
            }
            if (errno == EAGAIN || errno == ENOBUFS) {
                struct pollfd pfd {};
                pfd.fd = fd;
                pfd.events = POLLOUT;
                (void)poll(&pfd, 1, 50);
                continue;
            }
            return false;
        }
        return false;
    }
    return false;
}

static void OpenVPNApplyLargeSocketBuffers(int fd) {
    // Default datagram socket buffers are small; OpenVPN can outpace a slow main-queue relay and fill the pair.
    const int bufBytes = 4 * 1024 * 1024;
    int v = bufBytes;
    (void)setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &v, (socklen_t)sizeof(v));
    v = bufBytes;
    (void)setsockopt(fd, SOL_SOCKET, SO_SNDBUF, &v, (socklen_t)sizeof(v));
}

static NSArray<NSString *> *OpenVPNResolvedIpv4Strings(NSString *hostname) {
    if (hostname.length == 0) {
        return @[];
    }
    struct addrinfo hints {};
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_STREAM;
    struct addrinfo *res = nullptr;
    const char *host = hostname.UTF8String;
    if (!host) {
        return @[];
    }
    if (getaddrinfo(host, nullptr, &hints, &res) != 0) {
        return @[];
    }
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    for (struct addrinfo *p = res; p != nullptr; p = p->ai_next) {
        if (p->ai_family != AF_INET || p->ai_addr == nullptr) {
            continue;
        }
        auto *sin = reinterpret_cast<struct sockaddr_in *>(p->ai_addr);
        char buf[INET_ADDRSTRLEN];
        if (inet_ntop(AF_INET, &sin->sin_addr, buf, sizeof(buf)) == nullptr) {
            continue;
        }
        [out addObject:[NSString stringWithUTF8String:buf]];
    }
    freeaddrinfo(res);
    return out;
}

class PacketTunnelOpenVPNClient final : public openvpn::ClientAPI::OpenVPNClient {
  public:
    explicit PacketTunnelOpenVPNClient(OpenVPNRunnerBridge *__unsafe_unretained bridge, OpenVPNRunnerLogHandler logHandler)
        : bridge_(bridge), logHandler_(logHandler) {}

    bool pause_on_connection_timeout() override {
        logLine(@"[OpenVPN3] pause_on_connection_timeout -> false");
        return false;
    }

    void event(const openvpn::ClientAPI::Event &ev) override {
        logLine([NSString stringWithFormat:@"[OpenVPN3] event: %@ (%@)", ToNSString(ev.name), ToNSString(ev.info)]);
    }

    void acc_event(const openvpn::ClientAPI::AppCustomControlMessageEvent &ev) override {
        logLine([NSString stringWithFormat:@"[OpenVPN3] acc_event: protocol=%@ payload=%@",
                                               ToNSString(ev.protocol),
                                               ToNSString(ev.payload)]);
    }

    void log(const openvpn::ClientAPI::LogInfo &info) override {
        NSString *text = ToNSString(info.text);
        if ([text rangeOfString:@"No buffer space available"].location != NSNotFound
            || [text rangeOfString:@"TUN write exception"].location != NSNotFound) {
            if (![bridge_ allowSocketPressureLog]) {
                return;
            }
        }
        logLine([NSString stringWithFormat:@"[OpenVPN3] log: %@", text]);
    }

    void external_pki_cert_request(openvpn::ClientAPI::ExternalPKICertRequest &req) override {
        req.error = true;
        req.errorText = "External PKI is not implemented in DataGateMacPacketTunnel";
        logLine(@"[OpenVPN3] external_pki_cert_request: not implemented");
    }

    void external_pki_sign_request(openvpn::ClientAPI::ExternalPKISignRequest &req) override {
        req.error = true;
        req.errorText = "External PKI is not implemented in DataGateMacPacketTunnel";
        logLine(@"[OpenVPN3] external_pki_sign_request: not implemented");
    }

    bool tun_builder_new() override {
        [bridge_ openvpnTunBuilderReset];
        logLine(@"[OpenVPN3] tun_builder_new()");
        return true;
    }

    bool tun_builder_set_layer(int layer) override {
        logLine([NSString stringWithFormat:@"[OpenVPN3] tun_builder_set_layer(%d)", layer]);
        return layer == 3;
    }

    bool tun_builder_set_remote_address(const std::string &address, bool ipv6) override {
        logLine([NSString stringWithFormat:@"[OpenVPN3] tun_builder_set_remote_address(%@, ipv6=%@)",
                                           ToNSString(address),
                                           ipv6 ? @"true" : @"false"]);
        return true;
    }

    bool tun_builder_add_address(const std::string &address,
                                 int prefix_length,
                                 const std::string &gateway,
                                 bool ipv6,
                                 bool net30) override {
        if (!ipv6) {
            [bridge_ openvpnTunBuilderAddIpv4Address:ToNSString(address)
                                        prefixLength:prefix_length
                                             gateway:ToNSString(gateway)];
        }
        logLine([NSString stringWithFormat:@"[OpenVPN3] tun_builder_add_address(%@/%d, gw=%@, ipv6=%@, net30=%@)",
                                           ToNSString(address),
                                           prefix_length,
                                           ToNSString(gateway),
                                           ipv6 ? @"true" : @"false",
                                           net30 ? @"true" : @"false"]);
        return true;
    }

    bool tun_builder_set_route_metric_default(int metric) override {
        logLine([NSString stringWithFormat:@"[OpenVPN3] tun_builder_set_route_metric_default(%d)", metric]);
        return true;
    }

    bool tun_builder_reroute_gw(bool ipv4, bool ipv6, unsigned int flags) override {
        [bridge_ openvpnTunBuilderSetRerouteGwIpv4:ipv4 ipv6:ipv6 flags:flags];
        logLine([NSString stringWithFormat:@"[OpenVPN3] tun_builder_reroute_gw(ipv4=%@, ipv6=%@, flags=%u)",
                                           ipv4 ? @"true" : @"false",
                                           ipv6 ? @"true" : @"false",
                                           flags]);
        return true;
    }

    bool tun_builder_add_route(const std::string &address,
                               int prefix_length,
                               int metric,
                               bool ipv6) override {
        logLine([NSString stringWithFormat:@"[OpenVPN3] tun_builder_add_route(%@/%d, metric=%d, ipv6=%@)",
                                           ToNSString(address),
                                           prefix_length,
                                           metric,
                                           ipv6 ? @"true" : @"false"]);
        return true;
    }

    bool tun_builder_exclude_route(const std::string &address,
                                   int prefix_length,
                                   int metric,
                                   bool ipv6) override {
        if (!ipv6) {
            [bridge_ openvpnTunBuilderAppendExcludedIpv4:ToNSString(address) prefixLength:prefix_length];
        }
        logLine([NSString stringWithFormat:@"[OpenVPN3] tun_builder_exclude_route(%@/%d, metric=%d, ipv6=%@)",
                                           ToNSString(address),
                                           prefix_length,
                                           metric,
                                           ipv6 ? @"true" : @"false"]);
        return true;
    }

    bool tun_builder_set_dns_options(const openvpn::DnsOptions &dns) override {
        NSMutableArray<NSString *> *ipv4Servers = [NSMutableArray array];
        for (const auto &kv : dns.servers) {
            for (const auto &addr : kv.second.addresses) {
                if (addr.address.find(':') != std::string::npos) {
                    continue;
                }
                NSString *s = ToNSString(addr.address);
                if (s.length > 0) {
                    [ipv4Servers addObject:s];
                }
            }
        }
        [bridge_ openvpnTunBuilderReplaceDnsIpv4Servers:ipv4Servers];
        logLine([NSString stringWithFormat:@"[OpenVPN3] tun_builder_set_dns_options(servers=%lu, search=%lu)",
                                           (unsigned long)dns.servers.size(),
                                           (unsigned long)dns.search_domains.size()]);
        return true;
    }

    bool tun_builder_set_mtu(int mtu) override {
        [bridge_ openvpnTunBuilderSetMtuValue:mtu];
        logLine([NSString stringWithFormat:@"[OpenVPN3] tun_builder_set_mtu(%d)", mtu]);
        return true;
    }

    bool tun_builder_set_session_name(const std::string &name) override {
        logLine([NSString stringWithFormat:@"[OpenVPN3] tun_builder_set_session_name(%@)", ToNSString(name)]);
        return true;
    }

    bool tun_builder_add_proxy_bypass(const std::string &bypass_host) override {
        logLine([NSString stringWithFormat:@"[OpenVPN3] tun_builder_add_proxy_bypass(%@)", ToNSString(bypass_host)]);
        return true;
    }

    bool tun_builder_set_proxy_auto_config_url(const std::string &url) override {
        logLine([NSString stringWithFormat:@"[OpenVPN3] tun_builder_set_proxy_auto_config_url(%@)", ToNSString(url)]);
        return true;
    }

    bool tun_builder_set_proxy_http(const std::string &host, int port) override {
        logLine([NSString stringWithFormat:@"[OpenVPN3] tun_builder_set_proxy_http(%@:%d)", ToNSString(host), port]);
        return true;
    }

    bool tun_builder_set_proxy_https(const std::string &host, int port) override {
        logLine([NSString stringWithFormat:@"[OpenVPN3] tun_builder_set_proxy_https(%@:%d)", ToNSString(host), port]);
        return true;
    }

    bool tun_builder_add_wins_server(const std::string &address) override {
        logLine([NSString stringWithFormat:@"[OpenVPN3] tun_builder_add_wins_server(%@)", ToNSString(address)]);
        return true;
    }

    bool tun_builder_set_allow_family(int af, bool allow) override {
        logLine([NSString stringWithFormat:@"[OpenVPN3] tun_builder_set_allow_family(af=%d, allow=%@)",
                                           af,
                                           allow ? @"true" : @"false"]);
        return true;
    }

    bool tun_builder_set_allow_local_dns(bool allow) override {
        logLine([NSString stringWithFormat:@"[OpenVPN3] tun_builder_set_allow_local_dns(%@)", allow ? @"true" : @"false"]);
        return true;
    }

    int tun_builder_establish() override {
        const int fd = [bridge_ openvpnTunEstablishSocketPair];
        logLine([NSString stringWithFormat:@"[OpenVPN3] tun_builder_establish() -> %d (socketpair relay to NEPacketTunnelFlow)", fd]);
        return fd;
    }

    bool tun_builder_persist() override {
        return false;
    }

    void tun_builder_teardown(bool disconnect) override {
        logLine([NSString stringWithFormat:@"[OpenVPN3] tun_builder_teardown(disconnect=%@)", disconnect ? @"true" : @"false"]);
        [bridge_ openvpnTunTeardown];
    }

  private:
    void logLine(NSString *line) {
        if (logHandler_) {
            logHandler_(line);
        }
    }

    OpenVPNRunnerBridge *__unsafe_unretained bridge_;
    OpenVPNRunnerLogHandler logHandler_;
};

static NSError *OpenVPNRunnerError(NSInteger code, NSString *description) {
    return [NSError errorWithDomain:@"OpenVPNRunnerBridge"
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: description}];
}

} // namespace

@implementation OpenVPNRunnerBridge {
    std::unique_ptr<openvpn::ClientAPI::OpenVPNClientHelper> _helper;
    std::unique_ptr<PacketTunnelOpenVPNClient> _client;
    openvpn::ClientAPI::EvalConfig _evalConfig;
    std::unique_ptr<std::thread> _connectThread;
    std::atomic<bool> _prepared;
    std::atomic<bool> _connectRunning;

    NEPacketTunnelFlow *_packetFlow;
    int _tunOvpnFd;
    int _tunPeerFd;
    dispatch_queue_t _tunRelayQueue;
    std::atomic<bool> _tunRelayStop;

    BOOL _accumHasIpv4;
    NSString *_accumIpv4Addr;
    NSString *_accumIpv4Mask;
    NSString *_accumIpv4Gateway;
    BOOL _accumRerouteGwIpv4;
    NSMutableArray<NEIPv4Route *> *_accumExcludedRoutes;
    NSMutableArray<NSString *> *_accumDnsServers;
    int _accumMtu;

    OpenVPNNetworkSettingsHandler _networkSettingsHandler;
    NSString *_wssHostnameForExclude;
    CFAbsoluteTime _socketPressureLogDedupeAt;
}

- (instancetype)initWithLogHandler:(OpenVPNRunnerLogHandler)logHandler {
    self = [super init];
    if (self) {
        _logHandler = [logHandler copy];
        _helper = std::make_unique<openvpn::ClientAPI::OpenVPNClientHelper>();
        _client = std::make_unique<PacketTunnelOpenVPNClient>(self, _logHandler);
        _prepared = false;
        _connectRunning = false;
        _tunOvpnFd = -1;
        _tunPeerFd = -1;
        _tunRelayStop = true;
        const dispatch_queue_attr_t qosAttr =
            dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INTERACTIVE, 0);
        _tunRelayQueue = dispatch_queue_create("OpenVPNRunnerBridge.tunRelay", qosAttr);
        _socketPressureLogDedupeAt = 0;
        _accumExcludedRoutes = [NSMutableArray array];
        _accumDnsServers = [NSMutableArray array];
        _accumMtu = 0;
        _accumHasIpv4 = NO;
        _accumRerouteGwIpv4 = NO;
        _wssHostnameForExclude = @"";
    }
    return self;
}

- (void)setNetworkSettingsUpdateHandler:(OpenVPNNetworkSettingsHandler)handler {
    @synchronized(self) {
        _networkSettingsHandler = [handler copy];
    }
}

- (void)setWssProxyHostnameForExclusion:(NSString *)hostname {
    @synchronized(self) {
        _wssHostnameForExclude = hostname.length > 0 ? [hostname copy] : @"";
    }
}

- (void)setPacketFlow:(NEPacketTunnelFlow *)packetFlow {
    @synchronized(self) {
        _packetFlow = packetFlow;
    }
}

- (BOOL)allowSocketPressureLog {
    @synchronized(self) {
        const CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
        if (now - _socketPressureLogDedupeAt < 3.0) {
            return NO;
        }
        _socketPressureLogDedupeAt = now;
        return YES;
    }
}

- (void)injectDataPacketsFromTunnel:(NSArray<NSData *> *)packets protocols:(NSArray<NSNumber *> *)protocols {
    int peer = -1;
    @synchronized(self) {
        peer = _tunPeerFd;
    }
    if (peer < 0) {
        return;
    }
    const NSUInteger n = packets.count;
    for (NSUInteger i = 0; i < n; i++) {
        if (i >= protocols.count) {
            break;
        }
        NSData *ip = packets[i];
        if (ip.length == 0) {
            continue;
        }
        const int family = protocols[i].intValue;
        uint32_t hdr = htonl((uint32_t)family);
        NSMutableData *frame = [NSMutableData dataWithBytes:&hdr length:sizeof(hdr)];
        [frame appendData:ip];
        if (!OpenVPNDatagramSendWithPollWait(peer, frame.bytes, frame.length)) {
            if (_logHandler && [self allowSocketPressureLog]) {
                _logHandler([NSString stringWithFormat:@"[OpenVPN3] inject send failed errno=%d", errno]);
            }
            break;
        }
    }
}

- (int)openvpnTunEstablishSocketPair {
    int outFd = -1;
    @synchronized(self) {
        if (_tunOvpnFd >= 0) {
            return _tunOvpnFd;
        }
        if (!_packetFlow) {
            if (_logHandler) {
                _logHandler(@"[OpenVPN3] tun_builder_establish: packetFlow is nil; call setPacketFlow before start");
            }
            return -1;
        }
        int sp[2];
        if (socketpair(AF_UNIX, SOCK_DGRAM, 0, sp) != 0) {
            if (_logHandler) {
                _logHandler([NSString stringWithFormat:@"[OpenVPN3] socketpair failed errno=%d", errno]);
            }
            return -1;
        }
        fcntl(sp[0], F_SETFD, FD_CLOEXEC);
        fcntl(sp[1], F_SETFD, FD_CLOEXEC);
        OpenVPNApplyLargeSocketBuffers(sp[0]);
        OpenVPNApplyLargeSocketBuffers(sp[1]);
        _tunOvpnFd = sp[0];
        _tunPeerFd = sp[1];
        _tunRelayStop.store(false, std::memory_order_release);
        outFd = _tunOvpnFd;
    }
    __weak typeof(self) weakSelf = self;
    dispatch_async(_tunRelayQueue, ^{
        [weakSelf tunRelayRecvLoop];
    });
    dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf applyConsolidatedNetworkSettingsIfNeeded];
    });
    return outFd;
}

- (void)tunRelayRecvLoop {
    const NSUInteger kMaxBatchPackets = 48;
    for (;;) {
        if (_tunRelayStop.load(std::memory_order_acquire)) {
            break;
        }
        int peer = -1;
        NEPacketTunnelFlow *flow = nil;
        @synchronized(self) {
            peer = _tunPeerFd;
            flow = _packetFlow;
        }
        if (peer < 0) {
            break;
        }
        if (!flow) {
            continue;
        }
        uint8_t buf[65536];
        NSMutableArray<NSData *> *packetBatch = [NSMutableArray arrayWithCapacity:kMaxBatchPackets];
        NSMutableArray<NSNumber *> *protoBatch = [NSMutableArray arrayWithCapacity:kMaxBatchPackets];
        ssize_t n = recv(peer, buf, sizeof(buf), 0);
        if (n == 0) {
            break;
        }
        if (n < 0) {
            if (errno == EINTR) {
                continue;
            }
            break;
        }
        while (true) {
            if (n < 5) {
                break;
            }
            const uint8_t ver = (buf[4] >> 4) & 0x0FU;
            NSNumber *afNum = nil;
            if (ver == 4) {
                afNum = @(AF_INET);
            } else if (ver == 6) {
                afNum = @(AF_INET6);
            } else {
                break;
            }
            NSData *payload = [NSData dataWithBytes:buf + 4 length:(NSUInteger)(n - 4)];
            [packetBatch addObject:payload];
            [protoBatch addObject:afNum];
            if (packetBatch.count >= kMaxBatchPackets) {
                break;
            }
            ssize_t n2 = 0;
            do {
                n2 = recv(peer, buf, sizeof(buf), MSG_DONTWAIT);
            } while (n2 < 0 && errno == EINTR);
            if (n2 < 0) {
                if (errno == EAGAIN || errno == EWOULDBLOCK) {
                    break;
                }
                break;
            }
            if (n2 == 0) {
                break;
            }
            n = n2;
        }
        if (packetBatch.count == 0) {
            continue;
        }
        [flow writePackets:packetBatch withProtocols:protoBatch];
    }
}

- (void)openvpnTunBuilderReset {
    @synchronized(self) {
        _accumHasIpv4 = NO;
        _accumIpv4Addr = nil;
        _accumIpv4Mask = nil;
        _accumIpv4Gateway = nil;
        _accumRerouteGwIpv4 = NO;
        [_accumExcludedRoutes removeAllObjects];
        [_accumDnsServers removeAllObjects];
        _accumMtu = 0;
    }
}

- (void)openvpnTunBuilderAddIpv4Address:(NSString *)address prefixLength:(int)prefixLength gateway:(NSString *)gateway {
    if (address.length == 0) {
        return;
    }
    @synchronized(self) {
        _accumHasIpv4 = YES;
        _accumIpv4Addr = [address copy];
        _accumIpv4Mask = [OpenVPNSubnetMaskStringForPrefixLength(prefixLength) copy];
        _accumIpv4Gateway = [gateway copy];
    }
}

- (void)openvpnTunBuilderSetRerouteGwIpv4:(BOOL)ipv4 ipv6:(BOOL)ipv6 flags:(unsigned int)flags {
    (void)ipv6;
    (void)flags;
    @synchronized(self) {
        _accumRerouteGwIpv4 = ipv4;
    }
}

- (void)openvpnTunBuilderAppendExcludedIpv4:(NSString *)destination prefixLength:(int)prefixLength {
    if (destination.length == 0 || prefixLength < 0 || prefixLength > 32) {
        return;
    }
    NEIPv4Route *route = [[NEIPv4Route alloc] initWithDestinationAddress:destination
                                                                subnetMask:OpenVPNSubnetMaskStringForPrefixLength(prefixLength)];
    @synchronized(self) {
        [_accumExcludedRoutes addObject:route];
    }
}

- (void)openvpnTunBuilderReplaceDnsIpv4Servers:(NSArray<NSString *> *)servers {
    @synchronized(self) {
        [_accumDnsServers removeAllObjects];
        if (servers.count > 0) {
            [_accumDnsServers addObjectsFromArray:servers];
        }
    }
}

- (void)openvpnTunBuilderSetMtuValue:(int)mtu {
    @synchronized(self) {
        _accumMtu = mtu;
    }
}

- (void)applyConsolidatedNetworkSettingsIfNeeded {
    OpenVPNNetworkSettingsHandler handlerCopy = nil;
    BOOL hasIpv4 = NO;
    NSString *addr = nil;
    NSString *mask = nil;
    NSString *gateway = nil;
    BOOL rerouteGw = NO;
    NSArray<NEIPv4Route *> *excludedFromPush = nil;
    NSArray<NSString *> *dnsServers = nil;
    NSString *wssHost = nil;
    int mtu = 0;
    @synchronized(self) {
        hasIpv4 = _accumHasIpv4;
        addr = [_accumIpv4Addr copy];
        mask = [_accumIpv4Mask copy];
        gateway = [_accumIpv4Gateway copy];
        rerouteGw = _accumRerouteGwIpv4;
        excludedFromPush = [_accumExcludedRoutes copy];
        dnsServers = [_accumDnsServers copy];
        wssHost = [_wssHostnameForExclude copy];
        mtu = _accumMtu;
        handlerCopy = [_networkSettingsHandler copy];
    }
    if (!hasIpv4 || addr.length == 0 || mask.length == 0) {
        if (_logHandler) {
            _logHandler(@"[OpenVPN3] NE update skipped: no IPv4 address from server push");
        }
        return;
    }
    if (!handlerCopy) {
        if (_logHandler) {
            _logHandler(@"[OpenVPN3] NE update skipped: networkSettingsUpdateHandler is nil");
        }
        return;
    }
    NSMutableArray<NEIPv4Route *> *excluded = excludedFromPush ? [excludedFromPush mutableCopy] : [NSMutableArray array];
    [excluded addObject:[[NEIPv4Route alloc] initWithDestinationAddress:@"127.0.0.0" subnetMask:@"255.0.0.0"]];
    for (NSString *ip in OpenVPNResolvedIpv4Strings(wssHost)) {
        [excluded addObject:[[NEIPv4Route alloc] initWithDestinationAddress:ip subnetMask:@"255.255.255.255"]];
    }
    NSString *remote = gateway.length > 0 ? gateway : @"0.0.0.0";
    NEPacketTunnelNetworkSettings *settings = [[NEPacketTunnelNetworkSettings alloc] initWithTunnelRemoteAddress:remote];
    NEIPv4Settings *ipv4 = [[NEIPv4Settings alloc] initWithAddresses:@[addr] subnetMasks:@[mask]];
    if (rerouteGw) {
        ipv4.includedRoutes = @[ [NEIPv4Route defaultRoute] ];
    }
    ipv4.excludedRoutes = excluded;
    settings.IPv4Settings = ipv4;
    settings.MTU = (mtu > 0 && mtu < 65535) ? @(mtu) : @1500;
    if (@available(macOS 11.0, *)) {
        if (dnsServers.count > 0) {
            NEDNSSettings *dns = [[NEDNSSettings alloc] initWithServers:dnsServers];
            dns.matchDomains = @[ @"" ];
            settings.DNSSettings = dns;
        }
    }
    if (_logHandler) {
        _logHandler([NSString stringWithFormat:@"[OpenVPN3] posting NE settings: client=%@/%@ gw=%@ rerouteGwIpv4=%@ excludedRoutes=%lu dnsServers=%lu wssExcludeHost=%@",
                                               addr,
                                               mask,
                                               gateway,
                                               rerouteGw ? @"true" : @"false",
                                               (unsigned long)excluded.count,
                                               (unsigned long)dnsServers.count,
                                               wssHost.length ? wssHost : @"(none)"]);
    }
    handlerCopy(settings);
}

- (void)openvpnTunTeardown {
    _tunRelayStop.store(true, std::memory_order_release);
    int peerToClose = -1;
    @synchronized(self) {
        peerToClose = _tunPeerFd;
        _tunPeerFd = -1;
        _tunOvpnFd = -1;
    }
    if (peerToClose >= 0) {
        shutdown(peerToClose, SHUT_RDWR);
        close(peerToClose);
    }
}

- (BOOL)prepareWithOvpnContent:(NSString *)ovpnContent error:(NSError *__autoreleasing *)error {
    if (ovpnContent.length == 0) {
        if (error) {
            *error = OpenVPNRunnerError(1, @"OVPN content is empty.");
        }
        return NO;
    }

    const std::string content([ovpnContent UTF8String] ?: "");
    openvpn::ClientAPI::Config config;
    config.content = content;
    config.guiVersion = "DataGateMac 1.0";
    config.clockTickMS = 0;

    const openvpn::ClientAPI::EvalConfig eval = _client->eval_config(config);
    if (eval.error) {
        NSString *message = [NSString stringWithUTF8String:eval.message.c_str()] ?: @"OpenVPN3 eval_config failed.";
        if (error) {
            *error = OpenVPNRunnerError(2, message);
        }
        return NO;
    }
    _evalConfig = eval;
    _prepared = true;

    if (_logHandler) {
        const NSString *platform = [NSString stringWithUTF8String:openvpn::ClientAPI::OpenVPNClientHelper::platform().c_str()] ?: @"(unknown)";
        const NSString *remoteHost = [NSString stringWithUTF8String:eval.remoteHost.c_str()] ?: @"";
        const NSString *remotePort = [NSString stringWithUTF8String:eval.remotePort.c_str()] ?: @"";
        const NSString *remoteProto = [NSString stringWithUTF8String:eval.remoteProto.c_str()] ?: @"";
        _logHandler([NSString stringWithFormat:@"[OpenVPN3] platform=%@", platform]);
        _logHandler([NSString stringWithFormat:@"[OpenVPN3] eval_config OK: remote=%@:%@ proto=%@", remoteHost, remotePort, remoteProto]);
        _logHandler([NSString stringWithFormat:@"[OpenVPN3] eval_config auth: autologin=%@ externalPki=%@ profile=%@",
                                               eval.autologin ? @"true" : @"false",
                                               eval.externalPki ? @"true" : @"false",
                                               ToNSString(eval.profileName)]);
    }

    return YES;
}

- (void)start {
    if (!_prepared) {
        if (_logHandler) {
            _logHandler(@"[OpenVPN3] start skipped: prepare() was not called");
        }
        return;
    }
    if (_connectRunning.exchange(true)) {
        if (_logHandler) {
            _logHandler(@"[OpenVPN3] start skipped: connect() already running");
        }
        return;
    }

    if (!_evalConfig.autologin) {
        if (_logHandler) {
            _logHandler(@"[OpenVPN3] connect() not started: profile requires credentials and provide_creds() is not wired yet");
        }
        _connectRunning = false;
        return;
    }

    if (_logHandler) {
        _logHandler(@"[OpenVPN3] starting connect() on worker thread");
    }
    OpenVPNRunnerBridge *bridge = self;
    _connectThread = std::make_unique<std::thread>([bridge] {
        const openvpn::ClientAPI::Status status = bridge->_client->connect();
        if (bridge->_logHandler) {
            bridge->_logHandler([NSString stringWithFormat:@"[OpenVPN3] connect() finished: error=%@ status=%@ message=%@",
                                                           status.error ? @"true" : @"false",
                                                           ToNSString(status.status),
                                                           ToNSString(status.message)]);
        }
        bridge->_connectRunning = false;
    });
}

- (void)stop {
    if (_client) {
        _client->stop();
    }
    if (_connectThread && _connectThread->joinable()) {
        _connectThread->join();
    }
    _connectThread.reset();
    _connectRunning = false;
    @synchronized(self) {
        _networkSettingsHandler = nil;
    }
    [self openvpnTunTeardown];
}

@end
