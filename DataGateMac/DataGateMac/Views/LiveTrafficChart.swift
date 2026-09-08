//
//  LiveTrafficChart.swift
//  DataGateMac
//
//  OpenVPN-style live throughput from the local tunnel interface.
//

import Charts
import SwiftUI

struct LiveTrafficChart: View {
    let samples: [LiveTrafficSample]
    let bytesIn: UInt64
    let bytesOut: UInt64
    let downBytesPerSec: Double
    let upBytesPerSec: Double

    private var chartRows: [Row] {
        samples.flatMap { sample in
            [
                Row(at: sample.at, direction: .down, bytesPerSec: sample.downBytesPerSec),
                Row(at: sample.at, direction: .up, bytesPerSec: sample.upBytesPerSec),
            ]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            IconSectionTitle(
                title: L10n.tr("home_traffic", "Traffic"),
                systemImage: "chart.xyaxis.line"
            )
            Text(L10n.tr("home_traffic_hint", "Live throughput on this Mac through the VPN tunnel."))
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                rateTile(
                    title: L10n.tr("home_traffic_down", "Download"),
                    rate: downBytesPerSec,
                    total: bytesIn,
                    color: .green
                )
                rateTile(
                    title: L10n.tr("home_traffic_up", "Upload"),
                    rate: upBytesPerSec,
                    total: bytesOut,
                    color: .orange
                )
            }

            if samples.count >= 2 {
                Chart(chartRows) { row in
                    AreaMark(
                        x: .value("t", row.at),
                        y: .value("rate", row.bytesPerSec)
                    )
                    .foregroundStyle(by: .value("dir", row.direction.title))
                    .opacity(0.22)
                    .interpolationMethod(.catmullRom)
                    LineMark(
                        x: .value("t", row.at),
                        y: .value("rate", row.bytesPerSec)
                    )
                    .foregroundStyle(by: .value("dir", row.direction.title))
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }
                .chartForegroundStyleScale([
                    Direction.down.title: Color.green,
                    Direction.up.title: Color.orange,
                ])
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let rate = value.as(Double.self) {
                                Text(Self.formatRate(rate))
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .chartLegend(position: .bottom, alignment: .leading)
                .frame(height: 160)
            } else {
                Text(L10n.tr("home_traffic_waiting", "Waiting for traffic…"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80, alignment: .center)
            }
        }
    }

    private func rateTile(title: String, rate: Double, total: UInt64, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(Self.formatRate(rate))
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(color)
                .monospacedDigit()
            Text(Self.formatBytes(total))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func formatBytes(_ value: UInt64) -> String {
        let clamped = value > UInt64(Int64.max) ? Int64.max : Int64(value)
        return ByteCountFormatter.string(fromByteCount: clamped, countStyle: .binary)
    }

    static func formatRate(_ bytesPerSec: Double) -> String {
        let n = max(0, bytesPerSec)
        let text = formatBytes(UInt64(n.rounded()))
        return L10n.trFormat("home_rate_per_sec_fmt", "%@/s", text)
    }

    private struct Row: Identifiable {
        let at: Date
        let direction: Direction
        let bytesPerSec: Double
        var id: String { "\(at.timeIntervalSince1970)-\(direction.rawValue)" }
    }

    private enum Direction: String {
        case down
        case up

        var title: String {
            switch self {
            case .down: return L10n.tr("home_traffic_down", "Download")
            case .up: return L10n.tr("home_traffic_up", "Upload")
            }
        }
    }
}
