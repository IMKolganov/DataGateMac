# DataGateMac engine — OpenVPN 3 core for macOS

This directory builds the **OpenVPN 3 core** as a static library for macOS, mirroring the approach used in **DataGateWin/engine**: same source set from the `openvpn3` git submodule, same dependency set (OpenSSL, fmt, jsoncpp, lz4, xxhash, asio).

## Purpose

- **DataGateWin:** The engine is a separate `.exe` that links `ovpn3-core`, implements the WSS bridge (TCP/UDP↔WebSocket), session control, and TUN via Wintun; the UI talks to it over Named Pipes (IPC).
- **DataGateMac:** We use the same **ovpn3-core** library so we can run the same VPN + WSS logic. The “engine” on Mac can be either:
  1. **Inside the Packet Tunnel extension** — link `libovpn3-core.a` (and later a WSS bridge + session layer) into the **DataGateMacPacketTunnel** target; the extension then runs OpenVPN over a local TCP↔WSS bridge and uses `NEPacketTunnelProvider`’s `packetFlow` as the TUN.
  2. **Separate process** (optional) — a small `engine` binary that uses Unix domain sockets for IPC (like Named Pipes on Windows), implements the same bridge + session + OpenVPN, and uses **utun** (macOS) for the TUN; the app would start it and talk over sockets.

So far this folder only builds **ovpn3-core**. The WSS bridge and session code (from DataGateWin) can be ported here and either linked into the extension or into a separate engine binary.

## Dependencies (macOS, Homebrew)

Same logical deps as DataGateWin/engine (OpenSSL, fmt, jsoncpp, lz4, xxhash, asio); on Mac we use Homebrew:

```bash
brew install asio cmake fmt jsoncpp lz4 openssl pkg-config xxhash
```

| Package   | Purpose (openvpn3) |
|----------|----------------------|
| OpenSSL  | TLS/crypto           |
| asio     | Async I/O (header-only) |
| fmt      | Formatting           |
| jsoncpp  | JSON (optional in core) |
| lz4      | Compression          |
| xxhash   | Hashing              |

## Build (from repo root)

**Apple Silicon (arm64):**

```bash
git submodule update --init --recursive   # ensure openvpn3 is present
mkdir -p build-engine && cd build-engine
cmake -DOPENSSL_ROOT_DIR=/opt/homebrew/opt/openssl -DCMAKE_PREFIX_PATH=/opt/homebrew ../engine
cmake --build .
```

**Intel (x86_64):**

```bash
mkdir -p build-engine && cd build-engine
cmake -DOPENSSL_ROOT_DIR=/usr/local/opt/openssl -DCMAKE_PREFIX_PATH=/usr/local/opt ../engine
cmake --build .
```

Output: **`build-engine/libovpn3-core.a`** (static library).

## What gets built

- **ovpn3-core** — static library from the same openvpn3 sources as DataGateWin:
  - `openvpn3/client/*.cpp` (e.g. `ovpncli.cpp`)
  - `openvpn3/openvpn/*.cpp` (e.g. `openvpn/crypto/data_epoch.cpp`)
  - Excluded: `openvpn/ovpnagent/*`, `openvpn/omi/openvpn.cpp` (same as Windows).

Defines: `USE_ASIO`, `USE_OPENSSL`, `HAVE_LZ4`, `ASIO_STANDALONE`. Linked with macOS frameworks: CoreFoundation, IOKit, CoreServices, SystemConfiguration.

## Next steps (architecture parity with Windows)

1. **WSS bridge (TCP)** — Port or reuse DataGateWin’s `TcpWssBridge` / `WssLocalBridge`: listen on `127.0.0.1:port`, open WebSocket to `wss://host:port/path`, relay bytes. Build as part of `engine/` (e.g. a `datagate-bridge` lib or same executable).
2. **Session / config** — Port `OvpnConfigProcessor`, `SessionController`, `BridgeManager`-style logic so we can pass OVPN content + WSS options and start/stop the tunnel.
3. **TUN on Mac** — Either:
   - **In extension:** Implement a thin adapter that feeds OpenVPN from `NEPacketTunnelProvider.packetFlow` (read/write packets) instead of a real TUN fd; or
   - **Standalone engine:** Use openvpn3’s Mac TUN (e.g. `openvpn/tun/mac/`) with **utun** and run the engine as a separate process; the app would start it and use Unix sockets for IPC (GetStatus, StartSession, StopSession).
4. **Link into extension** — Add `libovpn3-core.a` (and later the bridge/session lib) to the **DataGateMacPacketTunnel** target in Xcode; call into C++ from Swift via a small C bridge or run the VPN loop on a thread.

This keeps the same “core + bridge + session + TUN” layering as on Windows, with platform-specific IPC and TUN (Named Pipes + Wintun on Windows; extension or Unix sockets + utun/packetFlow on Mac).
