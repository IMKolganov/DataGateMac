<p align="center">
  <img src="assets/logo.png" width="120" alt="DataGate" />
</p>

<h1 align="center">DataGate</h1>
<p align="center"><strong>macOS 🍎 VPN client — OpenVPN over WebSocket Secure (WSS)</strong></p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2013%2B-000000?logo=apple" alt="macOS 13+" />
  <img src="https://img.shields.io/badge/Swift-5.9-orange?logo=swift" alt="Swift 5.9" />
  <img src="https://img.shields.io/badge/OpenVPN-WSS-green" alt="OpenVPN over WSS" />
</p>

---

## What is this?

**DataGate** is a native macOS app that connects to your VPN backend and establishes an **OpenVPN** tunnel. Traffic is carried over **WebSocket Secure (WSS)** from the machine to your server, which then forwards it to the real OpenVPN server. That lets you run OpenVPN behind HTTPS/WSS (e.g. nginx) and avoid direct UDP/TCP to the VPN port.

- **App** gets config and WSS URL from your API, manages auth and UI (SwiftUI).
- **Network Extension** (if used) runs the OpenVPN core and a local TCP↔WSS bridge inside the system tunnel process.

Implementation guide: [NETWORK_EXTENSION.md](NETWORK_EXTENSION.md).

## Features

| Feature | Description |
|--------|-------------|
| **OpenVPN over WSS** | Tunnel traffic over WebSocket Secure; no direct VPN port exposure. |
| **SwiftUI** | Native macOS UI with Connect/Disconnect, status, and settings. |
| **Backend API** | Config and WSS URL from your API; optional auth (e.g. Google Sign-In). |
| **Themes** | Light and dark appearance. |

## Requirements

- **macOS 13.0+** (Ventura or later)
- **Xcode 15+**
- **Swift 5.9+**
- **CMake** (if building mbedTLS for a VPN extension), e.g. `brew install cmake`

## Setup

### 1. Clone and open

```bash
git clone <repo-url>
cd DataGateMac
git submodule update --init --recursive   # fetch openvpn3
```

### 2. API and auth config

If the app uses a backend, copy the example config and set your values (e.g. `Config.example.plist` → `Config.plist` with **APIBaseURL** and optional **GIDClientID**). Config files are typically in `.gitignore`.

### 3. Build in Xcode

Open the `.xcodeproj` or `.xcworkspace`, select the **DataGateMac** scheme and **My Mac**, then build (⌘B).

## Project layout

| Path | Description |
|------|-------------|
| **DataGateMac/** | Main app (Swift, SwiftUI) and Packet Tunnel extension. |
| **openvpn3/** | OpenVPN 3 core (git submodule); build for macOS to use in the extension. |
| **assets/** | Logo and images for the repo (e.g. README). |

## Building OpenVPN 3 for macOS

The **openvpn3** directory is a git submodule ([OpenVPN/openvpn3](https://github.com/OpenVPN/openvpn3)). Build it on macOS to link into the Packet Tunnel extension (WSS bridge + OpenVPN core).

**Dependencies (Homebrew):**

```bash
brew install asio cmake fmt jsoncpp lz4 openssl pkg-config xxhash
```

**Build (from repo root):**

- Apple Silicon (arm64):

  ```bash
  mkdir -p build-openvpn3 && cd build-openvpn3
  cmake -DOPENSSL_ROOT_DIR=/opt/homebrew/opt/openssl -DCMAKE_PREFIX_PATH=/opt/homebrew ../openvpn3
  cmake --build .
  ```

- Intel (x86_64):

  ```bash
  mkdir -p build-openvpn3 && cd build-openvpn3
  cmake -DOPENSSL_ROOT_DIR=/usr/local/opt/openssl -DCMAKE_PREFIX_PATH=/usr/local/opt ../openvpn3
  cmake --build .
  ```

Output: library and CLI in `build-openvpn3`. To use in the extension, you can build a static or dynamic library and add it to the **DataGateMacPacketTunnel** target (e.g. via a CMake-generated Xcode project or by adding the built library in Xcode). See [openvpn3/README.md](openvpn3/README.md) and [NETWORK_EXTENSION.md](NETWORK_EXTENSION.md).

## License

See `LICENSE.md`.
