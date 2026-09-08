//
//  ManualProfilesPageView.swift
//  DataGateMac
//
//  Import and connect local OpenVPN / VLESS profiles (no backend).
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ManualProfilesPageView: View {
    @ObservedObject var vm: VpnViewModel
    @State private var profiles: [ManualVpnProfile] = []
    @State private var loadError: String?
    @State private var actionError: String?
    @State private var showAddSheet = false
    @State private var profilePendingDelete: ManualVpnProfile?
    @State private var profilePendingRename: ManualVpnProfile?
    @State private var profilePendingEdit: ManualVpnProfile?
    @State private var renameDraft = ""

    private let store = ManualVpnProfileStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                IconSectionTitle(title: L10n.tr("profiles_title", "Profiles"), systemImage: "list.bullet.rectangle.fill", style: .page)
                Spacer()
                Button {
                    showAddSheet = true
                } label: {
                    Label(L10n.tr("profiles_add", "Add profile"), systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            Text(L10n.tr("profiles_subtitle", "Import an OpenVPN .ovpn file or a VLESS link and connect without using DataGate servers."))
                .font(.callout)
                .foregroundStyle(.secondary)

            if let loadError {
                Label(loadError, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
            if let actionError {
                Label(actionError, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            statusCard

            if profiles.isEmpty && loadError == nil {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(profiles) { profile in
                            profileCard(profile)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(24)
        .frame(minWidth: 500, maxWidth: .infinity, minHeight: 300, maxHeight: .infinity, alignment: .topLeading)
        .onDrop(of: [.fileURL, .utf8PlainText], isTargeted: nil, perform: handleDrop)
        .task {
            await vm.ensureConfigurationLoaded(refreshServers: false)
            reloadProfiles()
        }
        .sheet(isPresented: $showAddSheet) {
            AddManualProfileSheet(existing: nil) { draft in
                try saveDraft(draft, replacing: nil)
            }
        }
        .sheet(item: $profilePendingEdit) { profile in
            AddManualProfileSheet(existing: profile) { draft in
                try saveDraft(draft, replacing: profile)
            }
        }
        .alert(
            L10n.tr("profiles_rename_title", "Rename profile"),
            isPresented: Binding(
                get: { profilePendingRename != nil },
                set: { if !$0 { profilePendingRename = nil } }
            )
        ) {
            TextField(L10n.tr("profiles_name_placeholder", "Profile name"), text: $renameDraft)
            Button(L10n.tr("profiles_save", "Save")) {
                renameCurrent()
            }
            Button(L10n.tr("profiles_cancel", "Cancel"), role: .cancel) {
                profilePendingRename = nil
            }
        }
        .confirmationDialog(
            L10n.tr("profiles_delete_title", "Delete this profile?"),
            isPresented: Binding(
                get: { profilePendingDelete != nil },
                set: { if !$0 { profilePendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(L10n.tr("profiles_delete", "Delete"), role: .destructive) {
                deleteCurrent()
            }
            Button(L10n.tr("profiles_cancel", "Cancel"), role: .cancel) {
                profilePendingDelete = nil
            }
        } message: {
            if let name = profilePendingDelete?.displayName {
                Text(String(
                    format: L10n.tr("profiles_delete_confirm_fmt", "“%@” will be removed from this Mac. The VPN disconnects if this profile is active."),
                    locale: L10n.activeLocaleForFormatting(),
                    name
                ))
            }
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            IconSectionTitle(title: L10n.tr("home_conn_status", "Connection status"), systemImage: "checkmark.shield.fill")
            Text(vm.statusText)
                .foregroundStyle(.secondary)
            TunnelSessionIdentityList(rows: vm.connectionIdentityRows)
            if !vm.recentConnectLogExcerpt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(vm.recentConnectLogExcerpt)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.95))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            IconSectionTitle(title: L10n.tr("profiles_empty", "No local profiles yet."), systemImage: "tray")
            Text(L10n.tr("profiles_empty_hint", "Add an OpenVPN or Xray (VLESS) profile with the button above. You can also drop a file here."))
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.95))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private func profileCard(_ profile: ManualVpnProfile) -> some View {
        let connected = vm.isManualProfileConnected(profile.id)
        let missingPayload = profile.payload.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(profile.displayName)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text(kindLabel(profile.kind))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if connected {
                    Text(L10n.tr("profiles_connected_badge", "Connected"))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.green)
                }
            }
            if missingPayload {
                Text(L10n.tr("profiles_err_missing_payload", "The saved file for this profile is missing. Edit or delete it."))
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if let lastError = vm.lastManualConnectErrorById[profile.id], !lastError.isEmpty {
                Text(lastError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
            HStack(spacing: 10) {
                if connected {
                    Button {
                        vm.disconnect()
                    } label: {
                        Label(L10n.tr("home_disconnect", "Disconnect"), systemImage: "stop.fill")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!vm.canTapDisconnect)
                } else {
                    Button {
                        vm.connectManualProfile(id: profile.id)
                    } label: {
                        Label(L10n.tr("home_connect", "Connect"), systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!vm.canTapManualConnect || missingPayload)
                }
            }
            HStack(spacing: 10) {
                Button {
                    profilePendingEdit = profile
                } label: {
                    Label(L10n.tr("profiles_edit", "Edit"), systemImage: "pencil")
                }
                .buttonStyle(.bordered)
                Button {
                    renameDraft = profile.displayName
                    profilePendingRename = profile
                } label: {
                    Label(L10n.tr("profiles_rename", "Rename"), systemImage: "character.cursor.ibeam")
                }
                .buttonStyle(.bordered)
                Button(role: .destructive) {
                    profilePendingDelete = profile
                } label: {
                    Label(L10n.tr("profiles_delete", "Delete"), systemImage: "trash")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.95))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(connected ? Color.green.opacity(0.35) : Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private func kindLabel(_ kind: ManualVpnProfileKind) -> String {
        switch kind {
        case .openVpn:
            return L10n.tr("profiles_kind_openvpn", "OpenVPN")
        case .xray:
            return L10n.tr("profiles_kind_xray", "Xray")
        }
    }

    private func reloadProfiles() {
        do {
            profiles = try store.list()
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func renameCurrent() {
        guard let profile = profilePendingRename else { return }
        do {
            try store.rename(id: profile.id, displayName: renameDraft)
            actionError = nil
            reloadProfiles()
            if let name = ManualVpnProfileImporter.sanitizeDisplayName(renameDraft) {
                vm.noteRenamedManualProfile(id: profile.id, displayName: name)
            }
        } catch {
            actionError = error.localizedDescription
        }
        profilePendingRename = nil
    }

    private func deleteCurrent() {
        guard let profile = profilePendingDelete else { return }
        if vm.isManualProfileConnected(profile.id) {
            vm.disconnect()
        }
        do {
            try store.delete(id: profile.id)
            vm.clearManualConnectError(id: profile.id)
            actionError = nil
            reloadProfiles()
        } catch {
            actionError = error.localizedDescription
        }
        profilePendingDelete = nil
    }

    private func saveDraft(_ draft: ManualVpnProfileDraft, replacing existing: ManualVpnProfile?) throws {
        if let existing {
            let payloadChanged =
                existing.kind != draft.kind
                || ManualVpnProfileStore.normalizedPayload(existing.payload) != ManualVpnProfileStore.normalizedPayload(draft.payload)
            let updated = try store.replace(id: existing.id, draft: draft)
            vm.noteRenamedManualProfile(id: updated.id, displayName: updated.displayName)
            if payloadChanged, vm.isManualProfileConnected(updated.id) {
                vm.connectManualProfile(id: updated.id)
            }
        } else {
            _ = try store.add(draft)
        }
        actionError = nil
        reloadProfiles()
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url: URL?
                if let value = item as? URL {
                    url = value
                } else if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let string = item as? String {
                    url = URL(string: string)
                } else {
                    url = nil
                }
                guard let url else { return }
                DispatchQueue.main.async {
                    importFile(at: url)
                }
            }
            return true
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.utf8PlainText.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.utf8PlainText.identifier, options: nil) { item, _ in
                let text: String?
                if let value = item as? String {
                    text = value
                } else if let data = item as? Data {
                    text = String(data: data, encoding: .utf8)
                } else {
                    text = nil
                }
                guard let text else { return }
                DispatchQueue.main.async {
                    importRaw(text, fileName: nil)
                }
            }
            return true
        }
        return false
    }

    private func importFile(at url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        do {
            let text = try ManualVpnProfileImporter.readTextFile(at: url)
            importRaw(text, fileName: url.lastPathComponent)
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func importRaw(_ text: String, fileName: String?) {
        do {
            let draft = try ManualVpnProfileImporter.importPayload(text, fileName: fileName)
            _ = try store.add(draft)
            actionError = nil
            reloadProfiles()
        } catch {
            actionError = error.localizedDescription
        }
    }
}

private struct AddManualProfileSheet: View {
    let existing: ManualVpnProfile?
    let onSave: (ManualVpnProfileDraft) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var payload = ""
    @State private var kind: ManualVpnProfileKind = .openVpn
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(existing == nil
                 ? L10n.tr("profiles_add_title", "Add local profile")
                 : L10n.tr("profiles_edit_title", "Edit local profile"))
                .font(.title3)
                .fontWeight(.semibold)
            Text(L10n.tr("profiles_kind_label", "Type"))
                .font(.callout)
                .foregroundStyle(.secondary)
            Picker("", selection: $kind) {
                Text(L10n.tr("profiles_kind_openvpn", "OpenVPN")).tag(ManualVpnProfileKind.openVpn)
                Text(L10n.tr("profiles_kind_xray", "Xray (VLESS)")).tag(ManualVpnProfileKind.xray)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text(kindHint)
                .font(.callout)
                .foregroundStyle(.secondary)
            TextField(L10n.tr("profiles_name_placeholder", "Profile name"), text: $name)
            ZStack(alignment: .topLeading) {
                TextEditor(text: $payload)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 220)
                if payload.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(kindPlaceholder)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            }
            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.callout)
            }
            HStack {
                Button {
                    if let clip = NSPasteboard.general.string(forType: .string) {
                        payload = clip
                    }
                } label: {
                    Label(L10n.tr("profiles_paste", "Paste"), systemImage: "doc.on.clipboard")
                }
                Button {
                    pickFile()
                } label: {
                    Label(L10n.tr("profiles_import_file", "Import file…"), systemImage: "folder")
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Label(L10n.tr("profiles_cancel", "Cancel"), systemImage: "xmark")
                }
                Button {
                    save()
                } label: {
                    Label(L10n.tr("profiles_save", "Save"), systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .disabled(payload.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: 560, minHeight: 420)
        .onAppear {
            if let existing {
                name = existing.displayName
                payload = existing.payload
                kind = existing.kind
            }
        }
    }

    private var kindHint: String {
        switch kind {
        case .openVpn:
            return L10n.tr(
                "profiles_add_hint_openvpn",
                "Paste a full OpenVPN client config. Username/password files need embedded credentials; interactive login is not supported yet."
            )
        case .xray:
            return L10n.tr(
                "profiles_add_hint_xray",
                "Paste a vless:// link or JSON with vless / vlessXhttp."
            )
        }
    }

    private var kindPlaceholder: String {
        switch kind {
        case .openVpn:
            return L10n.tr("profiles_paste_placeholder_openvpn", "client / remote / <ca> …")
        case .xray:
            return L10n.tr("profiles_paste_placeholder_xray", "vless://… or { \"vless\": \"…\" }")
        }
    }

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        switch kind {
        case .openVpn:
            panel.allowedContentTypes = [
                UTType(filenameExtension: "ovpn") ?? .plainText,
                UTType(filenameExtension: "conf") ?? .plainText,
                .plainText,
                .item,
            ]
        case .xray:
            panel.allowedContentTypes = [
                .json,
                .plainText,
                .item,
            ]
        }
        if let window = filePickerHostWindow() {
            panel.beginSheetModal(for: window) { response in
                handlePickedFile(response: response, url: panel.url)
            }
        } else {
            panel.begin { response in
                handlePickedFile(response: response, url: panel.url)
            }
        }
    }

    private func filePickerHostWindow() -> NSWindow? {
        if let key = NSApp.keyWindow, key.sheetParent != nil {
            return key
        }
        if let sheet = NSApp.windows.reversed().first(where: { $0.isVisible && $0.sheetParent != nil }) {
            return sheet
        }
        return NSApp.keyWindow ?? NSApp.windows.first(where: \.isVisible)
    }

    private func handlePickedFile(response: NSApplication.ModalResponse, url: URL?) {
        guard response == .OK, let url else { return }
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        do {
            payload = try ManualVpnProfileImporter.readTextFile(at: url)
            if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                name = url.deletingPathExtension().lastPathComponent
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() {
        do {
            let preferred = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let draft = try ManualVpnProfileImporter.importPayload(
                payload,
                preferredName: preferred.isEmpty ? nil : preferred,
                expectedKind: kind
            )
            try onSave(draft)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
