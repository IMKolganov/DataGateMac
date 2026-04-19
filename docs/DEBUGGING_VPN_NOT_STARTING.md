# Debugging: VPN does not start in the app

This guide is for when the tunnel goes **Connecting → Disconnected** and you see an error (e.g. "Packet tunnel extension not available", code 14).

---

## How to find out why the extension didn’t start

Do these in order. The only way to get the **exact reason** from the system is step 1.

1. **Get the reason from system logs (recommended first)**  
   In Terminal, run and leave it running:
   ```bash
   log stream --predicate 'process == "networkextensiond" OR process == "neagent"' --level debug
   ```
   In the app tap **Connect**. In the Terminal output, look for lines that appear at the moment status goes to Disconnected — often there is an error or “extension not found” / code signing / path.  
   If you see nothing useful, try without the predicate (full log) and search for `networkextension`, `neagent`, your bundle ID, or “14”.

2. **Check that the extension is in the app that actually runs**  
   After a normal build, ensure the **same** app you run has the extension inside:
   ```bash
   # If you run from Xcode, use the Build/Products path (not Index.noindex):
   APP=~/Library/Developer/Xcode/DerivedData/DataGateMac-*/Build/Products/Debug/DataGateMac.app
   ls -la "$APP/Contents/PlugIns/"
   ```
   You must see `DataGateMacPacketTunnel.appex`. If PlugIns is empty, the extension is not embedded (see §2.1).

3. **Try running from /Applications**  
   Copy the built app to `/Applications`, run it from there (not from Xcode), then Connect. If it works only from /Applications, the system doesn’t load the extension when the app is run from DerivedData.

4. **Clean state**  
   Delete the VPN configuration in **System Settings → Network → VPN**. In Xcode: **Product → Clean Build Folder**, then build and run, tap Connect again.

5. **Confirm no debug dylibs in the extension**  
   In the **DataGateMacPacketTunnel** target set **ENABLE_DEBUG_DYLIB = NO**, clean build, then:
   ```bash
   find "$APP/Contents/PlugIns/DataGateMacPacketTunnel.appex" -name "*.dylib"
   ```
   There should be no `*.debug.dylib` or `__preview.dylib`.

If after step 1 you have a concrete error from the log (e.g. “bundle not found”, “signature invalid”), fix that. If the log is empty or unclear, steps 2–5 often resolve code 14.

**Typical log for code 14 when running from Xcode:**  
`LaunchServices: Cannot generate executableURL for app ... because it has no executable path stored (0)`  
`PlugInKit: Completed discovery. Final # of matches: 0`  
`NetworkExtension: Failed to find an app extension with identifier <your.PacketTunnel> and extension point com.apple.networkextension.packet-tunnel`  
`NEAgentSession: failed to initialize the delegate, shouldDisable 1`  

That means the daemon cannot see your extension (no path in Launch Services). **Run the app from /Applications** (copy the built .app there, then launch it) and try Connect again.

---

## 1. Where the failure happens

- **App** calls `startVPNTunnel()`. The system then starts the **Packet Tunnel extension** in a separate process and calls its `startTunnel(options:completionHandler:)`.
- If the **extension never runs**, you get code 14 and no extension logs in the UI (extension logs are written only after the extension process starts).
- So the break is between: “app requested start” and “extension’s `startTunnel` ran”.

---

## 1.1 Can I run the extension from the IDE or test it without the app?

**No.** The packet tunnel extension is not a normal app:

- There is **no “Run” for the extension target** in Xcode. The extension is started by the system (networkextensiond/neagent) only when the main app calls `startVPNTunnel()`. You cannot launch the `.appex` by itself.
- You **cannot test the extension without the app**: the system loads it in a separate process only in response to a VPN start request from your app.

**What you can do from the IDE:**

1. **Run the main app** (scheme DataGateMac) and use Connect as usual.
2. **Attach the debugger to the extension** after it has started:
   - Run the app from Xcode, tap Connect (extension must actually start for this to work).
   - In Xcode: **Debug → Attach to Process by PID or Name**.
   - Choose the extension process (e.g. **DataGateMacPacketTunnel** or **neagent**; you may need to try by PID from Activity Monitor).
   - Once attached, set breakpoints in `PacketTunnelProvider`, `WSSBridge`, etc.; they will hit on the next Connect or when the extension runs.
3. If you get **code 14**, the extension never starts, so there is **no process to attach to** until the cause of code 14 is fixed (bundle path, signing, running from /Applications, etc.).

---

## 1.2 Why not run from Xcode? How do developers develop and debug?

**Why Run from Xcode fails:** When you hit Run, the app starts from DerivedData. The system daemon (neagent) that loads the extension uses Launch Services to find your app and its extension. For apps launched from DerivedData, Launch Services often has no executable path stored for that context, so discovery returns 0 matches and you get code 14. This is a system limitation, not a bug in your code.

**Development and debugging still happen in Xcode.** You only change *where the app is launched from*:

1. **Edit and build in Xcode** — no change. Build the DataGateMac scheme as usual.
2. **Run the app from /Applications** — after each build (or when you need to test VPN), copy `DataGateMac.app` from `Build/Products/Debug/` to `/Applications` and launch it from there (e.g. double‑click in Finder). The extension will then be found.
3. **Debug the main app** — run from /Applications; to use Xcode debugger on the main app, use **Debug → Attach to Process by PID or Name** and choose **DataGateMac** after you have launched it from /Applications.
4. **Debug the extension** — with the app running from /Applications, tap Connect so the extension starts; then in Xcode use **Debug → Attach to Process by PID or Name** and choose **DataGateMacPacketTunnel** (or find its PID in Activity Monitor). Breakpoints in `PacketTunnelProvider` / `WSSBridge` will then hit.

**Optional: one-click “Run” that uses /Applications**  
Add a **Run Script** build phase or a **Post-action** on the scheme that copies the built app to `/Applications` and runs `open /Applications/DataGateMac.app`. Then “Run” in Xcode still builds and launches the app, but from /Applications, so the extension loads. You can also add a pre-action that kills any existing instance so the new build is the one that runs.

---

## 2. Checklist (in order)

### 2.1 Extension is in the app bundle

After a successful build:

```bash
# Replace with your actual DerivedData path if needed
APP=$(find ~/Library/Developer/Xcode/DerivedData -name "DataGateMac.app" -type d | head -1)
ls -la "$APP/Contents/PlugIns/"
# Should show: DataGateMacPacketTunnel.appex
```

If the `.appex` is missing, the extension target is not being built/copied (check scheme and Copy Files phase).

### 2.2 Extension entitlements and App Group

- Main app and extension must use the **same** App Group ID (e.g. `group.imkolganov.DataGateMac`).
- Both must have the **Network Extension** capability and the same team/signing.
- In Xcode: open both **DataGateMac** and **DataGateMacPacketTunnel** targets → Signing & Capabilities and compare.

### 2.3 No debug dylibs in the extension

Debug dylibs can prevent the system from loading the extension. In the **DataGateMacPacketTunnel** target:

- Build Settings → search **ENABLE_DEBUG_DYLIB** → set to **NO** for Debug and Release.

Then **Clean Build** and check that the `.appex` no longer contains `*.debug.dylib` or `__preview.dylib`:

```bash
find "$APP/Contents/PlugIns/DataGateMacPacketTunnel.appex" -name "*.dylib"
# Should list only system/framework dylibs, no debug/preview ones.
```

### 2.4 VPN configuration in System Settings

- **System Settings → Network → VPN**: if there is an old or broken DataGate VPN configuration, remove it.
- Run the app again and tap Connect so it creates a fresh configuration.

### 2.5 Run from a normal app location (to rule out path issues)

The daemon that loads the extension may expect the app in a standard location:

1. Build in Xcode (Product → Build).
2. Copy the built app to `/Applications` (or `~/Applications`):
   ```bash
   cp -R "$APP" /Applications/
   ```
3. Run **DataGateMac** from **Applications** (not from Xcode Run).
4. Try Connect again.

If it works only from `/Applications`, the issue is likely how the system resolves the app path when running from DerivedData.

---

## 3. System logs (why the system did not start the extension)

The exact reason for code 14 is often only in system logs. Do this **right after** reproducing the failure.

### Option A: Live stream (recommended)

In Terminal, start streaming **before** tapping Connect:

```bash
log stream --predicate 'process == "networkextensiond" OR process == "neagent"' --level debug
```

Then in the app tap **Connect**. Watch the Terminal output for errors or “extension not found” style messages.

### Option B: Last 2 minutes after the fact

```bash
log show --last 2m --predicate 'process == "networkextensiond" OR process == "neagent"' > ~/Desktop/NE_log.txt
open ~/Desktop/NE_log.txt
```

If the file is empty, try without the predicate (full log) and search for `networkextension`, `neagent`, `DataGateMac`, `PacketTunnel`, or your bundle ID.

### Option C: Console.app

1. Open **Console.app**.
2. Select your Mac in the sidebar.
3. In the search field use: `process:networkextensiond` or `process:neagent` or your app’s bundle ID.
4. Reproduce: tap Connect in the app.
5. Look for red (errors) or yellow (warnings) messages at the time of the failure.

---

## 4. App-side debugging in Xcode

- Set breakpoints in **VpnTunnelManager** where you call `startVPNTunnel()` and where you handle status changes and `fetchLastDisconnectError`.
- Confirm that:
  - `startVPNTunnel()` is called and does not throw.
  - Status goes to **Connecting** and then to **Disconnected**.
  - `lastError` / `fetchLastDisconnectError` gives the exact error (e.g. code 14).

This does not show *why* the system failed to start the extension; for that you need system logs (section 3).

---

## 5. If the extension *does* start but then stops

If you **do** see **Extension** logs in the app UI and then the tunnel disconnects:

- The failure is **inside** the extension (e.g. in `startTunnel`, WSSBridge, or network setup).
- Use those extension log lines to see how far it got.
- To attach the debugger to the extension: tap Connect, then in Xcode use **Debug → Attach to Process by PID or Name** and choose the extension process (e.g. **DataGateMacPacketTunnel** or **neagent**). Next runs you can set breakpoints in the extension and reproduce.

---

## 6. Summary

| Symptom | Likely place | What to do |
|--------|----------------|------------|
| Code 14, no extension logs in UI | System cannot load extension | Sections 2 and 3: bundle, entitlements, no debug dylibs, run from /Applications, then system logs |
| Extension logs appear then disconnect | Extension starts then fails | Section 5: use extension logs + attach debugger to extension process |
| Different error code | App or config | Section 4: breakpoints + `fetchLastDisconnectError` and system logs |
