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

### 3. Build and run in Xcode

- **One app, one scheme.** Open `DataGateMac/DataGateMac.xcodeproj`. There are two **targets** (DataGateMac app + DataGateMacPacketTunnel extension), but you **run only the app**: choose the **DataGateMac** scheme and **My Mac** as destination, then Run (⌘R). The extension is built and embedded into the app automatically; you do **not** run the extension as a second application.
- **Destination:** Use **My Mac** (real device). The Packet Tunnel extension does **not** run in the Simulator.
- **First run:** You may need to allow the app in **System Settings → Privacy & Security** and, for the VPN, approve the Network Extension in **System Settings → General → VPN & Network** (or when the system prompts).

## Project layout

| Path | Description |
|------|-------------|
| **DataGateMac/** | Main app (Swift, SwiftUI) and Packet Tunnel extension. |
| **openvpn3/** | OpenVPN 3 source (git submodule). |
| **engine/** | CMake build for macOS: produces `libovpn3-core.a` (same approach as DataGateWin/engine). |
| **assets/** | Logo and images for the repo (e.g. README). |

## Building OpenVPN 3 core for macOS

We build the same **OpenVPN 3 core** as DataGateWin (static library from the `openvpn3` submodule) using **engine/** so the same VPN + WSS logic can run on Mac (in the Packet Tunnel extension or a separate engine process). See [engine/README.md](engine/README.md) for architecture and next steps.

**Dependencies (Homebrew):**

```bash
brew install asio cmake fmt jsoncpp lz4 openssl pkg-config xxhash
```

**Build (from repo root):**

- Apple Silicon (arm64):

  ```bash
  mkdir -p build-engine && cd build-engine
  cmake -DOPENSSL_ROOT_DIR=/opt/homebrew/opt/openssl -DCMAKE_PREFIX_PATH=/opt/homebrew ../engine
  cmake --build .
  ```

- Intel (x86_64):

  ```bash
  mkdir -p build-engine && cd build-engine
  cmake -DOPENSSL_ROOT_DIR=/usr/local/opt/openssl -DCMAKE_PREFIX_PATH=/usr/local/opt ../engine
  cmake --build .
  ```

Output: **`build-engine/libovpn3-core.a`**. To use in the extension, add this static library to the **DataGateMacPacketTunnel** target in Xcode and implement (or port from DataGateWin) the WSS bridge + session layer. See [engine/README.md](engine/README.md) and [NETWORK_EXTENSION.md](NETWORK_EXTENSION.md).

## License

See `LICENSE.md`.
