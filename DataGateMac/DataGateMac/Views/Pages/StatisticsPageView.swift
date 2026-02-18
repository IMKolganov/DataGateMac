//
//  StatisticsPageView.swift
//  DataGateMac
//
//  Statistics with date filters and chart — matches OpenVpnGateMonitor overview.
//

import SwiftUI
import Charts

enum StatisticsPreset: String, CaseIterable {
    case last24h = "Last 24h"
    case last7d = "Last 7 days"
    case last30d = "Last 30 days"
    case thisMonth = "This month"
    case lastMonth = "Last month"
    case ytd = "YTD"
    case last1y = "Last year"
    case last3y = "Last 3 years"
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
                    Text("Statistics")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Spacer()
                    Button {
                        Task { await load() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
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
        .frame(minWidth: 500, maxWidth: .infinity, minHeight: 400, maxHeight: .infinity, alignment: .topLeading)
        .task {
            await load()
        }
    }

    private var dateFilterSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Date range")
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(StatisticsPreset.allCases, id: \.rawValue) { preset in
                        Button {
                            applyPreset(preset)
                        } label: {
                            Text(preset.rawValue)
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

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("From")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    DatePicker("", selection: $from, displayedComponents: .date)
                        .labelsHidden()
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("To")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    DatePicker("", selection: $to, displayedComponents: .date)
                        .labelsHidden()
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Grouping")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("", selection: $grouping) {
                        Text("Auto").tag(OverviewGrouping.auto)
                        Text("Hours").tag(OverviewGrouping.hours)
                        Text("Days").tag(OverviewGrouping.days)
                        Text("Months").tag(OverviewGrouping.months)
                        Text("Years").tag(OverviewGrouping.years)
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
                Button("Apply") {
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
            StatCard(title: "Users", value: "\(t.usersCount)")
            StatCard(title: "Sessions", value: "\(t.sessionsCount)")
            StatCard(title: "Traffic IN", value: formatBytes(t.trafficInBytes))
            StatCard(title: "Traffic OUT", value: formatBytes(t.trafficOutBytes))
            StatCard(title: "Traffic TOTAL", value: formatBytes(totalBytes))
        }
    }

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("User activity & traffic")
                .font(.headline)
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
            errorMessage = "Not authorized"
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

    var body: some View {
        if data.isEmpty {
            Text("No data")
                .foregroundStyle(.secondary)
                .frame(height: 280)
                .frame(maxWidth: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sessions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Chart(data) { point in
                        AreaMark(
                            x: .value("Time", point.label),
                            y: .value("Sessions", point.active)
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
                            x: .value("Time", point.label),
                            y: .value("Sessions", point.active)
                        )
                        .foregroundStyle(.blue)
                        .interpolationMethod(.catmullRom)
                    }
                    .frame(height: 120)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Traffic (MB)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Chart(data) { point in
                        AreaMark(
                            x: .value("Time", point.label),
                            y: .value("MB", Double(point.mb))
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
                            x: .value("Time", point.label),
                            y: .value("MB", Double(point.mb))
                        )
                        .foregroundStyle(.green)
                        .interpolationMethod(.catmullRom)
                    }
                    .frame(height: 120)
                }
            }
            .frame(height: 280)
        }
    }
}
