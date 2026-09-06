//
//  AccessPageView.swift
//  DataGateMac
//
//  Server list (table) + quota summary — matches Android Access screen.
//

import SwiftUI

struct AccessPageView: View {
    @ObservedObject var authState: AuthStateStore
    @State private var servers: [OpenVpnServerWithStatusDto] = []
    @State private var quotaState: QuotaSectionState = .empty
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var serverListError: String?

    private let serversApi = OpenVpnServersApiClient.shared
    private let quotaApi = QuotaPlanApiClient.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(L10n.tr("access_title", "Access"))
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button {
                    Task { await loadAll() }
                } label: {
                    Label(L10n.tr("access_refresh", "Refresh"), systemImage: "arrow.clockwise")
                }
                .disabled(isLoading)
            }

            if let error = errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if isLoading {
                            HStack(spacing: 10) {
                                ProgressView()
                                    .controlSize(.small)
                                Text(L10n.tr("access_loading", "Loading…"))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                        if let sErr = serverListError {
                            Label(sErr, systemImage: "exclamationmark.triangle")
                                .font(.callout)
                                .foregroundStyle(.red)
                        }
                        quotaSection
                        serverTableSection
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(24)
        .frame(minWidth: 500, maxWidth: .infinity, minHeight: 300, maxHeight: .infinity, alignment: .topLeading)
        .task {
            await loadAll()
        }
        .refreshable {
            await loadAll()
        }
        .onReceive(NotificationCenter.default.publisher(for: .appLanguageChanged)) { _ in
            Task { await loadAll() }
        }
    }

    private var quotaSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.tr("access_quota", "Quota"))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            if let err = quotaState.errorText, !err.isEmpty {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.tr("access_quota_current", "Current plan"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let name = quotaState.currentPlanName {
                        Text(name)
                            .font(.headline)
                        if let from = quotaState.currentEffectiveFrom?.trimmingCharacters(in: .whitespacesAndNewlines),
                           !from.isEmpty {
                            Text(String(
                                format: L10n.tr("access_effective_from_fmt", "Effective from: %@"),
                                locale: L10n.activeLocaleForFormatting(),
                                QuotaEffectiveFromDisplay.format(from)
                            ))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        if let note = quotaState.currentNote?.trimmingCharacters(in: .whitespacesAndNewlines),
                           !note.isEmpty {
                            Text(note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text(L10n.tr("access_no_quota", "No active quota assignment"))
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }

            trafficQuotaBlock

            if !quotaState.allPlans.isEmpty {
                Text(L10n.tr("access_all_plans", "All plans"))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                ForEach(quotaState.allPlans) { plan in
                    GroupBox {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(plan.name)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Spacer()
                                if plan.isDefault {
                                    Text(L10n.tr("plan_default", "Default"))
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.accentColor.opacity(0.15))
                                        .cornerRadius(4)
                                }
                                if !plan.isActive {
                                    Text(L10n.tr("plan_inactive", "Inactive"))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            if let desc = plan.description?.trimmingCharacters(in: .whitespacesAndNewlines),
                               !desc.isEmpty {
                                Text(desc)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(4)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var trafficQuotaBlock: some View {
        if let help = quotaState.trafficQuotaHelpText, !help.isEmpty {
            Text(help)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else if quotaState.trafficLimitBytes > 0, let used = quotaState.trafficUsedBytes, used >= 0 {
            let limit = quotaState.trafficLimitBytes
            let ratio = limit > 0 ? min(1.0, Double(used) / Double(limit)) : 0
            let pct = limit > 0 ? min(100.0, 100.0 * Double(used) / Double(limit)) : 0
            let over = used > limit
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.tr("access_traffic_quota", "Traffic quota"))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Text(
                    quotaState.trafficPeriodIsMonthly
                        ? L10n.tr("access_quota_period_month", "This calendar month")
                        : L10n.tr("access_quota_period_today", "Today")
                )
                .font(.caption)
                .foregroundStyle(.tertiary)
                ProgressView(value: ratio, total: 1.0)
                    .progressViewStyle(.linear)
                    .tint(over ? Color.red : nil)
                Text(trafficQuotaStatsLine(used: used, limit: limit, pct: pct, over: over))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 4)
        }
    }

    private func trafficQuotaStatsLine(used: Int64, limit: Int64, pct: Double, over: Bool) -> String {
        let uStr = ByteCountFormatter.string(fromByteCount: used, countStyle: .binary)
        let lStr = ByteCountFormatter.string(fromByteCount: limit, countStyle: .binary)
        let pctStr = String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), pct)
        let line1 = String(
            format: L10n.tr("access_quota_used_line_fmt", "Used %1$@ / %2$@ (%3$@%%)"),
            locale: L10n.activeLocaleForFormatting(),
            uStr,
            lStr,
            pctStr
        )
        if over {
            let overBy = ByteCountFormatter.string(fromByteCount: used - limit, countStyle: .binary)
            let line2 = String(
                format: L10n.tr("access_quota_over_fmt", "Over by %@"),
                locale: L10n.activeLocaleForFormatting(),
                overBy
            )
            return "\(line1)\n\(line2)"
        }
        let remaining = ByteCountFormatter.string(fromByteCount: limit - used, countStyle: .binary)
        let line2 = String(
            format: L10n.tr("access_quota_remaining_fmt", "Remaining %@"),
            locale: L10n.activeLocaleForFormatting(),
            remaining
        )
        return "\(line1)\n\(line2)"
    }

    @ViewBuilder
    private var serverTableSection: some View {
        if servers.isEmpty {
            Text(L10n.tr("access_no_servers", "No servers available"))
                .foregroundStyle(.secondary)
                .padding(.top, 8)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.tr("access_servers", "Servers"))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                serverTable
            }
        }
    }

    private func accessServerLabel(_ row: OpenVpnServerWithStatusDto) -> String {
        let server = row.openVpnServerResponses.openVpnServer
        var name = server.serverName
        if server.serverType == .xray {
            name += " · Xray"
            return name
        }
        if server.isEnableWss == true {
            name += L10n.tr("home_server_wss_suffix", " · WSS")
        } else {
            name += L10n.tr("home_server_openvpn_suffix", " · OpenVPN")
        }
        if let proto = server.listedLinkProtocol {
            name += " · \(proto)"
        }
        return name
    }

    private var serverTable: some View {
        Table(servers, columns: {
            TableColumn(L10n.tr("tbl_server", "Server")) { row in
                Text(accessServerLabel(row))
            }
            TableColumn(L10n.tr("tbl_clients", "Clients")) { row in
                Text("\(row.countConnectedClients)")
                    .monospacedDigit()
            }
            TableColumn(L10n.tr("tbl_in", "In")) { row in
                Text(formatBytes(row.totalBytesIn))
                    .monospacedDigit()
            }
            TableColumn(L10n.tr("tbl_out", "Out")) { row in
                Text(formatBytes(row.totalBytesOut))
                    .monospacedDigit()
            }
            TableColumn(L10n.tr("tbl_online", "Online")) { row in
                Image(systemName: (row.openVpnServerResponses.openVpnServer.isOnline ?? false) ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle((row.openVpnServerResponses.openVpnServer.isOnline ?? false) ? .green : .red)
            }
        })
        .frame(minHeight: 200)
    }

    @MainActor
    private func loadAll() async {
        guard let token = await authState.getValidAccessToken() else {
            errorMessage = L10n.tr("access_not_authorized", "Not authorized")
            serverListError = nil
            servers = []
            quotaState = .empty
            return
        }
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil
        serverListError = nil

        let uid = authState.resolvedUserId(accessToken: token)

        async let quotaTask: QuotaSectionState = loadQuotaState(token: token, userId: uid)

        do {
            servers = try await serversApi.getAllWithStatus(token: token, withoutCache: true)
            serverListError = nil
        } catch {
            serverListError = error.localizedDescription
            servers = []
        }

        quotaState = await quotaTask
        isLoading = false
    }

    @MainActor
    private func loadQuotaState(token: String, userId: Int?) async -> QuotaSectionState {
        guard let userId, userId > 0 else {
            return .empty
        }
        do {
            async let plansResp = quotaApi.getAllQuotaPlans(token: token, includeInactive: true)
            async let userResp = quotaApi.getUserQuotaPlansByUserId(token: token, userId: userId)
            let (p, u) = try await (plansResp, userResp)
            let planList = p.data?.quotaPlans ?? []
            let items = u.data?.items ?? []
            let base = QuotaSectionState.build(
                plansSuccess: p.success,
                plansMessage: p.message,
                userSuccess: u.success,
                userMessage: u.message,
                plans: planList,
                assignments: items
            )
            return await base.withOverviewTraffic(token: token, plans: planList, assignments: items)
        } catch {
            return QuotaSectionState(errorText: error.localizedDescription)
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .binary)
    }
}
