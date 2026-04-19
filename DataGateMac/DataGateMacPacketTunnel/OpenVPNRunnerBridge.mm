#import "OpenVPNRunnerBridge.h"

#include <arpa/inet.h>
#include <atomic>
#include <memory>
#include <netinet/in.h>
#include <sys/socket.h>
#include <string>
#include <thread>

#include "ovpncli.hpp"

namespace {

static NSString *ToNSString(const std::string &value) {
    return [NSString stringWithUTF8String:value.c_str()] ?: @"";
}

class PacketTunnelOpenVPNClient final : public openvpn::ClientAPI::OpenVPNClient {
  public:
    explicit PacketTunnelOpenVPNClient(OpenVPNRunnerLogHandler logHandler)
        : logHandler_(logHandler) {}

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
        logLine([NSString stringWithFormat:@"[OpenVPN3] log: %@", ToNSString(info.text)]);
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
        logLine([NSString stringWithFormat:@"[OpenVPN3] tun_builder_exclude_route(%@/%d, metric=%d, ipv6=%@)",
                                           ToNSString(address),
                                           prefix_length,
                                           metric,
                                           ipv6 ? @"true" : @"false"]);
        return true;
    }

    bool tun_builder_set_dns_options(const openvpn::DnsOptions &dns) override {
        logLine([NSString stringWithFormat:@"[OpenVPN3] tun_builder_set_dns_options(servers=%lu, search=%lu)",
                                           (unsigned long)dns.servers.size(),
                                           (unsigned long)dns.search_domains.size()]);
        return true;
    }

    bool tun_builder_set_mtu(int mtu) override {
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
        logLine(@"[OpenVPN3] tun_builder_establish() -> -1 (packetFlow adapter not wired yet)");
        return -1;
    }

    bool tun_builder_persist() override {
        return false;
    }

    void tun_builder_teardown(bool disconnect) override {
        logLine([NSString stringWithFormat:@"[OpenVPN3] tun_builder_teardown(disconnect=%@)", disconnect ? @"true" : @"false"]);
    }

  private:
    void logLine(NSString *line) {
        if (logHandler_) {
            logHandler_(line);
        }
    }

    OpenVPNRunnerLogHandler logHandler_;
};

static NSError *OpenVPNRunnerError(NSInteger code, NSString *description) {
    return [NSError errorWithDomain:@"OpenVPNRunnerBridge"
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: description}];
}

} // namespace

@interface OpenVPNRunnerBridge ()
@property (nonatomic, copy) OpenVPNRunnerLogHandler logHandler;
@end

@implementation OpenVPNRunnerBridge {
    std::unique_ptr<openvpn::ClientAPI::OpenVPNClientHelper> _helper;
    std::unique_ptr<PacketTunnelOpenVPNClient> _client;
    openvpn::ClientAPI::EvalConfig _evalConfig;
    std::unique_ptr<std::thread> _connectThread;
    std::atomic<bool> _prepared;
    std::atomic<bool> _connectRunning;
}

- (instancetype)initWithLogHandler:(OpenVPNRunnerLogHandler)logHandler {
    self = [super init];
    if (self) {
        _logHandler = [logHandler copy];
        _helper = std::make_unique<openvpn::ClientAPI::OpenVPNClientHelper>();
        _client = std::make_unique<PacketTunnelOpenVPNClient>(_logHandler);
        _prepared = false;
        _connectRunning = false;
    }
    return self;
}

- (BOOL)prepareWithOvpnContent:(NSString *)ovpnContent error:(NSError * _Nullable __autoreleasing *)error {
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
}

@end
