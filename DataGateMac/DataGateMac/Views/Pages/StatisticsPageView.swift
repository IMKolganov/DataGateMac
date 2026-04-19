//
//  StatisticsPageView.swift
//  DataGateMac
//
//  Statistics with date filters and chart — matches OpenVpnGateMonitor overview.
//

import SwiftUI
import Charts

enum StatisticsPreset: CaseIterable, Identifiable {
    case last24h
    case last7d
    case last30d
    case thisMonth
    case lastMonth
    case ytd
    case last1y
    case last3y

    var id: Self { self }

    var title: String {
        switch self {
        case .last24h: return L10n.tr("stats_preset_last24h", "Last 24h")
        case .last7d: return L10n.tr("stats_preset_last7d", "Last 7 days")
        case .last30d: return L10n.tr("stats_preset_last30d", "Last 30 days")
        case .thisMonth: return L10n.tr("stats_preset_this_month", "This month")
        case .lastMonth: return L10n.tr("stats_preset_last_month", "Last month")
        case .ytd: return L10n.tr("stats_preset_ytd", "YTD")
        case .last1y: return L10n.tr("stats_preset_last1y", "Last year")
        case .last3y: return L10n.tr("stats_preset_last3y", "Last 3 years")
        }
    }
}

struct ChartPoint: Identifiable {
    let id = UUID()
    let label: String
    let active: Int
    let mb: Int
}

struct StatisticsPageView: View {
    @ObservedObject var authState: AuthStateStore

    @State private var from = addDays(startOfToday(), -6)
    @State private var to = endOfToday()
    @State private var grouping: OverviewGrouping = .auto
    @State private var seriesRows: [OverviewSeriesRowDto] = []
    @State private var totals: TotalsPayloadDto?
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let api = StatisticsApiClient.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(L10n.tr("stats_title", "Statistics"))
                        .font(.title2)
                        .fontWeight(.semibold)
                    Spacer()
                    Button {
                        Task { await load() }
                    } label: {
                        Label(L10n.tr("stats_refresh", "Refresh"), systemImage: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                }

                dateFilterSection
                statsCardsSection
                chartSection

                if let error = errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
            .padding(24)
        }
        .frame(minWidth: 720, maxWidth: .infinity, minHeight: 400, maxHeight: .infinity, alignment: .topLeading)
        .task {
            await load()
        }
        .onReceive(NotificationCenter.default.publisher(for: .appLanguageChanged)) { _ in
            Task { await load() }
        }
    }

    private var dateFilterSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.tr("stats_date_range", "Date range"))
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(StatisticsPreset.allCases) { preset in
                        Button {
                            applyPreset(preset)
                        } label: {
                            Text(preset.title)
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(activePreset == preset ? Color.accentColor : Color.primary.opacity(0.08))
                                .foregroundStyle(activePreset == preset ? .white : .primary)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack(alignment: .center, spacing: 16) {
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.tr("stats_from", "From"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        DatePicker("", selection: $from, displayedComponents: .date)
                            .labelsHidden()
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.tr("stats_to", "To"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        DatePicker("", selection: $to, displayedComponents: .date)
                            .labelsHidden()
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.tr("stats_grouping", "Grouping"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Picker("", selection: $grouping) {
                            Text(L10n.tr("stats_group_auto", "Auto")).tag(OverviewGrouping.auto)
                            Text(L10n.tr("stats_group_hours", "Hours")).tag(OverviewGrouping.hours)
                            Text(L10n.tr("stats_group_days", "Days")).tag(OverviewGrouping.days)
                            Text(L10n.tr("stats_group_months", "Months")).tag(OverviewGrouping.months)
                            Text(L10n.tr("stats_group_years", "Years")).tag(OverviewGrouping.years)
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }
                }
                Spacer(minLength: 0)
                Button(L10n.tr("stats_apply", "Apply")) {
                    Task { await load() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var statsCardsSection: some View {
        let t = totals ?? TotalsPayloadDto(sessionsCount: 0, usersCount: 0, trafficInBytes: 0, trafficOutBytes: 0, trafficTotalBytes: nil)
        let totalBytes = t.trafficTotalBytes ?? (t.trafficInBytes + t.trafficOutBytes)
        return LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible()),
        ], spacing: 12) {
            StatCard(title: L10n.tr("stats_users", "Users"), value: "\(t.usersCount)")
            StatCard(title: L10n.tr("stats_sessions", "Sessions"), value: "\(t.sessionsCount)")
            StatCard(title: L10n.tr("stats_traffic_in", "Traffic IN"), value: formatBytes(t.trafficInBytes))
            StatCard(title: L10n.tr("stats_traffic_out", "Traffic OUT"), value: formatBytes(t.trafficOutBytes))
            StatCard(title: L10n.tr("stats_traffic_total", "Traffic TOTAL"), value: formatBytes(totalBytes))
        }
    }

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.tr("stats_activity_title", "User activity & traffic"))
                .font(.headline)
                .padding(.top, 8)
                .padding(.bottom, 18)
            if isLoading {
                ProgressView()
                    .frame(height: 280)
                    .frame(maxWidth: .infinity)
            } else {
                OverviewChartView(data: chartData)
            }
        }
        .padding()
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var chartData: [ChartPoint] {
        let mode = effectiveGrouping
        return seriesRows.compactMap { row -> ChartPoint? in
            guard !row.ts.isEmpty, let date = ISO8601DateFormatter().date(from: row.ts) else { return nil }
            let totalBytes = row.trafficTotalBytes ?? (row.trafficInBytes ?? 0) + (row.trafficOutBytes ?? 0)
            return ChartPoint(
                label: formatLabel(date, mode: mode),
                active: row.activeClients ?? 0,
                mb: Int(totalBytes / (1024 * 1024))
            )
        }
    }

    private var effectiveGrouping: String {
        switch grouping {
        case .auto:
            let span = to.timeIntervalSince(from)
            if span <= 2 * 86400 { return "hours" }
            if span <= 180 * 86400 { return "days" }
            if span <= 36 * 30 * 86400 { return "months" }
            return "years"
        case .hours: return "hours"
        case .days: return "days"
        case .months: return "months"
        case .years: return "years"
        }
    }

    private var activePreset: StatisticsPreset? {
        let now = Date()
        if isSameDay(from, addDays(startOfToday(), -6)),
           isSameDay(to, endOfToday()) { return .last7d }
        if isSameDay(from, addDays(startOfToday(), -29)),
           isSameDay(to, endOfToday()) { return .last30d }
        if isSameDay(from, startOfMonth(now)),
           isSameDay(to, endOfMonth(now)) { return .thisMonth }
        let lastM = addMonths(now, -1)
        if isSameDay(from, startOfMonth(lastM)),
           isSameDay(to, endOfMonth(lastM)) { return .lastMonth }
        let cal = Calendar.current
        if cal.component(.day, from: from) == 1 && cal.component(.month, from: from) == 1,
           isSameDay(to, now) { return .ytd }
        return nil
    }

    private func applyPreset(_ preset: StatisticsPreset) {
        let now = Date()
        switch preset {
        case .last24h:
            from = now.addingTimeInterval(-24 * 3600)
            to = now
        case .last7d:
            from = addDays(startOfToday(), -6)
            to = endOfToday()
        case .last30d:
            from = addDays(startOfToday(), -29)
            to = endOfToday()
        case .thisMonth:
            from = startOfMonth(now)
            to = endOfMonth(now)
        case .lastMonth:
            let lastM = addMonths(now, -1)
            from = startOfMonth(lastM)
            to = endOfMonth(lastM)
        case .ytd:
            from = Date(timeIntervalSince1970: 0)
            from = Calendar.current.date(from: DateComponents(year: Calendar.current.component(.year, from: now), month: 1, day: 1)) ?? from
            to = now
        case .last1y:
            from = addYears(now, -1)
            to = now
        case .last3y:
            from = addYears(now, -3)
            to = now
        }
        grouping = .auto
        Task { await load() }
    }

    @MainActor
    private func load() async {
        guard let token = await authState.getValidAccessToken() else {
            errorMessage = L10n.tr("access_not_authorized", "Not authorized")
            return
        }
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil

        let fromDate = from
        let toDate = to
        let groupingVal = grouping

        do {
            async let seriesTask = api.getOverviewSeries(token: token, from: fromDate, to: toDate, grouping: groupingVal)
            async let summaryTask = api.getOverviewSummary(token: token, from: fromDate, to: toDate)

            let (series, summary) = try await (seriesTask, summaryTask)
            seriesRows = series.overviewSeriesRows ?? []
            totals = summary.totals
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .binary)
    }

    private func formatLabel(_ date: Date, mode: String) -> String {
        let df = DateFormatter()
        df.locale = L10n.activeLocaleForFormatting()
        switch mode {
        case "hours":
            df.dateFormat = "HH:mm MMM d"
        case "days":
            df.dateFormat = "MMM d"
        case "months":
            df.dateFormat = "MMM yy"
        case "years":
            df.dateFormat = "yyyy"
        default:
            df.dateFormat = "MMM d"
        }
        return df.string(from: date)
    }
}

private func startOfToday() -> Date {
    Calendar.current.startOfDay(for: Date())
}

private func endOfToday() -> Date {
    let cal = Calendar.current
    var comps = cal.dateComponents([.year, .month, .day], from: Date())
    comps.hour = 23
    comps.minute = 59
    comps.second = 59
    return cal.date(from: comps) ?? Date()
}

private func addDays(_ d: Date, _ n: Int) -> Date {
    Calendar.current.date(byAdding: .day, value: n, to: d) ?? d
}

private func addMonths(_ d: Date, _ n: Int) -> Date {
    Calendar.current.date(byAdding: .month, value: n, to: d) ?? d
}

private func addYears(_ d: Date, _ n: Int) -> Date {
    Calendar.current.date(byAdding: .year, value: n, to: d) ?? d
}

private func startOfMonth(_ d: Date) -> Date {
    let cal = Calendar.current
    let comps = cal.dateComponents([.year, .month], from: d)
    return cal.date(from: comps) ?? d
}

private func endOfMonth(_ d: Date) -> Date {
    let cal = Calendar.current
    guard let next = cal.date(byAdding: .month, value: 1, to: d),
          let last = cal.date(byAdding: .day, value: -1, to: next) else { return d }
    var comps = cal.dateComponents([.year, .month, .day], from: last)
    comps.hour = 23
    comps.minute = 59
    comps.second = 59
    return cal.date(from: comps) ?? d
}

private func isSameDay(_ a: Date, _ b: Date) -> Bool {
    Calendar.current.isDate(a, inSameDayAs: b)
}

private struct StatCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct OverviewChartView: View {
    let data: [ChartPoint]
    @State private var selectedLabel: String?

    private var selectedPoint: ChartPoint? {
        guard let label = selectedLabel else { return nil }
        return data.first { $0.label == label }
    }

    private var axisTime: String { L10n.tr("stats_chart_axis_time", "Time") }
    private var axisSessions: String { L10n.tr("stats_chart_sessions", "Sessions") }
    private var axisMb: String { L10n.tr("stats_chart_axis_mb", "MB") }

    var body: some View {
        if data.isEmpty {
            Text(L10n.tr("stats_no_data", "No data"))
                .foregroundStyle(.secondary)
                .frame(height: 280)
                .frame(maxWidth: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.tr("stats_chart_sessions", "Sessions"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Chart(data) { point in
                        AreaMark(
                            x: .value(axisTime, point.label),
                            y: .value(axisSessions, point.active)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue.opacity(0.5), .blue.opacity(0.05)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.catmullRom)
                        LineMark(
                            x: .value(axisTime, point.label),
                            y: .value(axisSessions, point.active)
                        )
                        .foregroundStyle(.blue)
                        .interpolationMethod(.catmullRom)
                        if let sel = selectedLabel, sel == point.label {
                            RuleMark(x: .value(axisTime, point.label))
                                .foregroundStyle(.blue.opacity(0.5))
                                .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 4]))
                        }
                    }
                    .chartXSelection(value: $selectedLabel)
                    .frame(height: 138)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.tr("stats_chart_traffic_mb", "Traffic (MB)"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Chart(data) { point in
                        AreaMark(
                            x: .value(axisTime, point.label),
                            y: .value(axisMb, Double(point.mb))
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.green.opacity(0.4), .green.opacity(0.05)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.catmullRom)
                        LineMark(
                            x: .value(axisTime, point.label),
                            y: .value(axisMb, Double(point.mb))
                        )
                        .foregroundStyle(.green)
                        .interpolationMethod(.catmullRom)
                        if let sel = selectedLabel, sel == point.label {
                            RuleMark(x: .value(axisTime, point.label))
                                .foregroundStyle(.green.opacity(0.5))
                                .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 4]))
                        }
                    }
                    .chartXSelection(value: $selectedLabel)
                    .frame(height: 138)
                }

                ZStack(alignment: .leading) {
                    Color.clear
                        .frame(height: 28)
                    if let point = selectedPoint {
                        HStack(spacing: 16) {
                            Text(point.label)
                                .fontWeight(.medium)
                            Text(String(format: L10n.tr("stats_tooltip_sessions_fmt", "Sessions: %lld"), locale: L10n.activeLocaleForFormatting(), Int64(point.active)))
                                .foregroundStyle(.blue)
                            Text(String(format: L10n.tr("stats_tooltip_traffic_mb_fmt", "Traffic: %lld MB"), locale: L10n.activeLocaleForFormatting(), Int64(point.mb)))
                                .foregroundStyle(.green)
                        }
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
                .frame(height: 28)
                .padding(.bottom, 12)
            }
            .frame(height: 330)
        }
    }
}
