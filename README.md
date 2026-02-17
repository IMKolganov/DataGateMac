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
```

### 2. API and auth config

If the app uses a backend, copy the example config and set your values (e.g. `Config.example.plist` → `Config.plist` with **APIBaseURL** and optional **GIDClientID**). Config files are typically in `.gitignore`.

### 3. Build in Xcode

Open the `.xcodeproj` or `.xcworkspace`, select the **DataGateMac** scheme and **My Mac**, then build (⌘B).

## Project layout

| Path | Description |
|------|-------------|
| **DataGateMac/** | Main app (Swift, SwiftUI). |
| **assets/** | Logo and images for the repo (e.g. README). |

## License

See `LICENSE.md`.
