# VPN via Network Extension (as in README)

The approach from the README: the **App** manages config and UI; the **Network Extension** (Packet Tunnel) runs the OpenVPN core and a local TCP↔WSS bridge inside the system tunnel process. The tunnel lives in the system and can survive app restarts.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  DataGateMac (container app)                                     │
│  • Auth, API (servers, OVPN files), UI (SwiftUI)                 │
│  • NETunnelProviderManager: save config, Start/Stop tunnel        │
│  • Pass to extension: WSS URL, OVPN content (providerConfiguration)│
└──────────────────────────────┬──────────────────────────────────┘
                               │ system IPC (not Named Pipes)
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│  DataGateMacPacketTunnel (Network Extension)                     │
│  • NEPacketTunnelProvider                                       │
│  • Local TCP (127.0.0.1:port) ↔ WSS (host:port/path)              │
│  • OpenVPN core over that TCP (same idea as Engine on Windows)    │
│  • TUN interface for traffic                                     │
└─────────────────────────────────────────────────────────────────┘
```

---

## Lifecycle and communication (who starts what, who controls what)

### Who runs the extension?

- The **system (macOS)** runs the extension. The **app never “owns” the extension process**.
- When the app calls `connection.startVPNTunnel()`, the app is only asking the **system** to start the extension. The system then:
  - Starts a **separate process** for the Packet Tunnel provider.
  - Passes the saved configuration (and optional `startVPNTunnel(options:)` dict) into that process.
- So: **app → system → extension**. The app does not “launch” the extension binary directly; the system does.

### How does the extension “live” in memory?

- The extension process is **created by the system** when the tunnel is started and **destroyed** when the tunnel is stopped (or on crash).
- It can **outlive the app**: if you quit the app, the tunnel process may keep running (system keeps it alive). When you reopen the app, it uses `NETunnelProviderManager.loadAllFromPreferences` and gets the same `manager.connection`; observing `connection.status` still shows the real state (e.g. Connected).
- So the extension is a **short‑lived process per tunnel session**: start → run until stop/crash → process exits. There is no long‑lived “daemon” that stays in memory forever; the “tunnel” process is the extension process.

### Who controls it?

- **Start:** only the **app** (via `connection.startVPNTunnel()`). The app must have the manager loaded and call start.
- **Stop:** the **app** (via `connection.stopVPNTunnel()`). The system then terminates the extension process.
- **Configuration:** the **app** writes it (e.g. `providerConfiguration`) and **saves** it with `manager.saveToPreferences`. The extension only **reads** that config when the system starts it; the extension cannot “ask the app” for new config at runtime.

### How do app and extension exchange messages and state?

There is **no direct pipe/socket between app and extension** (unlike Windows Named Pipes).

| Direction | Mechanism | What you get |
|-----------|-----------|--------------|
| **App → Extension** | Only at **start** | 1) `providerConfiguration` (saved earlier in `NETunnelProviderProtocol`) — WSS host/port/path, OVPN content, etc. 2) Optional `startVPNTunnel(options: [String: NSObject])` — one-time dict when starting. No ongoing “commands” from app to extension. |
| **Extension → App** | **Indirect, via system** | 1) **Status:** the app observes `connection.status` (`NEVPNStatus`: invalid, disconnected, connecting, connected, reasserting, disconnecting). The **system** updates this based on extension lifecycle and `setTunnelNetworkSettings` / completionHandler. So the app gets “Connecting / Connected / Disconnected” without the extension sending messages. 2) **Logs / stats:** not provided by the framework. To get them you’d add your own channel (e.g. App Group + shared file or Darwin notifications, or a local socket the extension writes to and the app reads). |

So in practice:

- **Commands:** the only “commands” are **start** (with optional options dict) and **stop**. No GetStatus/StartSession-style RPC after start; the extension runs until stopped or crash.
- **State:** the app gets state from **`NEVPNStatus`** (system‑driven). No need for the extension to “report” status unless you want extra (logs, bytes in/out); then you add your own IPC (e.g. App Group).

### Short summary

1. **Start:** App saves config → App calls `startVPNTunnel()` → System starts extension process and passes config → Extension runs `startTunnel(options:completionHandler:)`.
2. **While running:** Extension does WSS bridge + OpenVPN, handles packets. App only observes `connection.status` (and optionally its own log/stats channel if implemented).
3. **Stop:** App calls `stopVPNTunnel()` → System stops the extension process.
4. **No ongoing app ↔ extension protocol** — only config at start and system status. For more, you add App Group / file / notifications yourself.

---

## Implementation steps

### 1. Add Network Extension target in Xcode

1. **File → New → Target…** → **macOS** → **Packet Tunnel Provider**.
2. Name e.g. **DataGateMacPacketTunnel**, bundle id: `imkolganov.DataGateMac.PacketTunnel` (or your domain).
3. Xcode will create:
   - A separate target with an `NEPacketTunnelProvider` subclass;
   - App Group (if you need to share data between app and extension) — optional.

**Important:** The extension runs only on a real Mac, not in the Simulator.

### 2. Entitlements

- **Container app (DataGateMac):**
  - In **Signing & Capabilities** add **App Groups** if you pass config via UserDefaults/group.
  - No special entitlement is required for using `NETunnelProviderManager`; the system grants VPN management when the API is used.

- **Extension (DataGateMacPacketTunnel):**
  - Capabilities will include **Network Extension: Packet Tunnel**.
  - Add the same **App Groups** as the container if the extension needs to read config from shared storage.

### 3. Container app: VPN configuration manager

In the main app:

1. **Load/save config** via `NETunnelProviderManager.loadAllFromPreferences` / `saveToPreferences`.
2. **Build tunnel config** (`NETunnelProviderProtocol`):
   - `providerBundleIdentifier` = your Packet Tunnel extension bundle id (e.g. `imkolganov.DataGateMac.PacketTunnel`);
   - `serverAddress` = display name (e.g. `"datagate"`);
   - **providerConfiguration** = `[String: Any]` with WSS host/port/path, OVPN content, etc.
3. **Start tunnel:** `connection.startVPNTunnel(options: nil)` on `NETunnelProviderSession`.
4. **Stop:** `connection.stopVPNTunnel()`.
5. **Observe status:** `NEVPNStatus` via `connection.status` (KVO or polling) and show Connecting / Connected / Disconnected in the UI.

You can build the StartSession-style config (WSS + OVPN) the same way as on Windows: pick server → API for device file (OVPN) → put host, port, path, ovpnContent into `providerConfiguration`.

**Connect flow (current implementation):**

1. User taps Connect on Home (MainView → HomePageView with `AuthStateStore`).
2. `VpnViewModel.connect()`: if `authState` and valid token exist, calls `TunnelConfigBuilder.build(token:)`; otherwise uses a placeholder config.
3. **TunnelConfigBuilder:** `InstallationIdService.getOrCreate()`, `JwtClaimReader.getExternalId(fromJwt:)`, `OpenVpnServersApiClient.getAllWithStatus(token:)` → pick best WSS server (online, `isEnableWss`, min `countConnectedClients`) → commonName `wdg-{serverId}-{externalId}-{installationId}` → `OpenVpnFilesApiClient.ensureAndDownloadDeviceFile(...)` (download-by-cn, or add-with-token then download) → build `TunnelConfig` from server `apiUrl` and OVPN content.
4. `VpnTunnelManager.setConfiguration(config)` then `startTunnel()`; status comes from `NEVPNStatus`.

If backend config fails (no server, no OVPN, API error), the app falls back to a placeholder config and still starts the tunnel (for testing); the log shows “Backend config failed, using placeholder.”

### 4. Extension: what to do in `startTunnel(options:completionHandler:)`

1. Read config from `protocolConfiguration as? NETunnelProviderProtocol` → `providerConfiguration`.
2. Parse: host, port, path (WSS), ovpnContent (or path to a temp .ovpn file).
3. In the background:
   - **WSS bridge:** listen on local TCP (e.g. `127.0.0.1:18080`), for each connection open a WebSocket to `wss://host:port/path` and relay data.
   - **OpenVPN:** connect the OpenVPN core to `127.0.0.1:18080` (same as the Windows Engine). Use an embedded library (e.g. openvpn3 with mbedTLS) or note that running an external binary from the extension is restricted in the sandbox.
4. Set **TUN interface** via `self.networkSettings` / `setTunnelNetworkSettings` (IP, mask, routes), then call `completionHandler(nil)`.
5. Packet handling: in `handlePacket` read packets from the tunnel and feed them to OpenVPN; from OpenVPN write back via `self.packetFlow.writePackets`.

Implementing OpenVPN inside the extension usually requires a C/C++ library (e.g. openvpn3) built as a framework and linked to the extension target. To link `libovpn3-core.a` (from `engine/` CMake build) you must also link its dependencies in the extension target: **OpenSSL** (`libssl`, `libcrypto`), **libc++**, and optionally fmt, lz4, etc., e.g. by adding the same libs to the extension’s “Link Binary With Libraries” and setting **Library Search Paths** (e.g. to Homebrew’s `/opt/homebrew/opt/openssl/lib`). Alternatively build a single fat library or XCFramework that includes ovpn3-core and all deps.

### 5. Component summary

| Component | Where | Role |
|-----------|--------|------|
| Server selection, auth, OVPN from API | App | **Implemented:** OpenVpnServersApiClient, OpenVpnFilesApiClient (download-by-cn, add-with-token), InstallationIdService, JwtClaimReader, TunnelConfigBuilder; VpnViewModel uses them when user is logged in. |
| NETunnelProviderManager | App | Save config, Start/Stop tunnel, expose NEVPNStatus to VpnViewModel. |
| Packet Tunnel Provider | Extension | startTunnel: WSS bridge + OpenVPN, setTunnelNetworkSettings, packetFlow. |

---

## Reference: OpenVPN Connect (official client) architecture

OpenVPN Connect for macOS uses a **similar split**:

- **GUI** — main app; user-facing UI, profiles, settings.
- **Daemon / helper process** — runs in the background and owns the actual VPN tunnel, separate from the GUI.
- **Config** — passed securely to the tunnel process (e.g. dynamic .ovpn, credentials from Keychain).
- **OpenVPN 3 library** — used for the protocol; on macOS the tunnel side often integrates with **NetworkExtension** (system tunnel process).

So: **UI + separate tunnel process/extension** is the same idea as DataGate (Windows: UI + Engine; macOS: App + Packet Tunnel). The main difference is transport: Windows uses Named Pipes and a custom engine binary; macOS uses the system’s Network Extension and `NETunnelProviderManager` to start/stop and pass config.
