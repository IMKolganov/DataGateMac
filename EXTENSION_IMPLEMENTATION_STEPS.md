# Packet Tunnel Extension: implementation steps

Goal: when the user taps Connect, the tunnel actually comes up and traffic flows over OpenVPN on top of WSS to your server.

**Reference:** For how to implement the OpenVPN + WSS bridge and TUN wiring, see the **DataGateWin** (Windows) or **iOS** project in the same repo—they already have a working flow; port the same logic here (engine, bridge, session, TUN adapter).

---

## Overview

```
[App] → startVPNTunnel() → [System starts extension]
                                  ↓
[PacketTunnelProvider] ← providerConfiguration (host, port, path, ovpnContent, listenPort)
         │
         ├─ 1. WSS bridge: TCP 127.0.0.1:listenPort ↔ WebSocket wss://host:port/path
         ├─ 2. OpenVPN: connects to 127.0.0.1:listenPort, sends/receives packets
         └─ 3. TUN: packetFlow ↔ OpenVPN (read packets, write packets)
```

---

## Step 1. WSS bridge (done)

- **Task:** Listen on TCP `127.0.0.1:listenPort`; for each client connection open a WebSocket to `wss://host:port/path` and relay bytes both ways.
- **In code:** `WSSBridge` (Network.framework `NWListener` + `NWConnection`, `URLSessionWebSocketTask`).
- **Result:** Any client (including OpenVPN) connecting to localhost:listenPort is behind the bridge and talks to the server over WSS.

---

## Step 2. OpenVPN in the extension (pending: build and link)

- **Task:** Run the OpenVPN client with config from `ovpnContent`, point its transport at `127.0.0.1:listenPort` (bridge from step 1). OpenVPN will produce/consume IP packets; wire them to `packetFlow`. Use **DataGateWin** or **iOS** as reference for the client/session/TUN layer.
- **Sub-steps:**
  - **2a. Build:** From repo root: `cd build-engine && cmake ../engine && cmake --build .` → `libovpn3-core.a`. Dependencies: OpenSSL, fmt, jsoncpp, lz4, xxhash, asio (Homebrew).
  - **2b. Link into extension:** In Xcode, for target DataGateMacPacketTunnel add `libovpn3-core.a`, `libssl.a`, `libcrypto.a`, their search paths (e.g. `/opt/homebrew/opt/openssl/lib`), and `-force_load` for static libs. Or build a single XCFramework with ovpn3 + OpenSSL for distribution.
  - **2c. C bridge:** Thin C/C++ layer with `extern "C"`: init OpenVPN client, set config (server = 127.0.0.1, port = listenPort, OVPN content), register callbacks for TUN read/write. Call from Swift via bridging header or C wrapper.
  - **2d. Wire to PacketFlowBridge:** The extension already has `PacketFlowBridge`: set `onPacketFromTun` to feed data into OpenVPN; when OpenVPN outputs packets call `packetFlowBridge.writePacketsToTun(_:protocols:)`.
  - **2e. Loop and thread:** OpenVPN 3 (ovpncli) uses ASIO/io_context; run it on a dedicated thread or DispatchQueue and keep the run loop active until stopTunnel.
- **Result:** After step 2 the tunnel will be real: addresses/routes from OpenVPN → `setTunnelNetworkSettings`, traffic via `packetFlow`.

---

## Step 3. Tunnel network settings

- **Current:** Placeholder (10.8.0.1/24) so the system considers the tunnel up.
- **After step 2:** Call `setTunnelNetworkSettings` with addresses and routes from OpenVPN (push route/ifconfig). Or keep the placeholder until the first successful OpenVPN connect, then update from push.

---

## Step 4. Lifecycle and shutdown

- On `stopTunnel` stop the WSS bridge (close listener and connections) and the OpenVPN session (once step 2 is done).
- On bridge or OpenVPN error call `cancelTunnelWithError` so the app shows Disconnected.

---

## Current status

| Step | Status |
|------|--------|
| 1. WSS bridge | Done (WSSBridge). |
| 2. OpenVPN | Not done: link ovpn3-core + OpenSSL and add C bridge (2a–2e). Reference DataGateWin / iOS. |
| 2.5. PacketFlow bridge | Done (PacketFlowBridge): read loop running, `onPacketFromTun` and `writePacketsToTun` ready for OpenVPN. |
| 3. Tunnel settings | Placeholder; after step 2 use OpenVPN push. |
| 4. Shutdown/errors | WSS and PacketFlowBridge stop in stopTunnel; on error use cancelTunnelWithError. |

After implementing step 2 (2a–2e) the connection will be end-to-end (same as Windows/Android/iOS).

---

## Debug logging

- **App:** Critical steps are logged to the "Engine logs" area on the main screen. Lines are prefixed with `[Connect flow]`, `[Tunnel]`, or `[Backend]` so you can see which step you’re on. All messages are in English.
- **Extension:** Logs go to the system log (os_log). In **Console.app** filter by subsystem `imkolganov.DataGateMac.PacketTunnel` or search for `[Ext]` / `[WSSBridge]` to see extension steps (Step 1–4, listener, client connect, etc.). Extension logs are not shown in the app UI.
