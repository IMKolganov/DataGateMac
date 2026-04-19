//
//  OverviewModels.swift
//  DataGateMac
//
//  Matches OpenVpnGateMonitor overview API responses.
//

import Foundation

// Grouping: 0=Auto, 1=Hours, 2=Days, 3=Months, 4=Years
enum OverviewGrouping: Int, Codable {
    case auto = 0
    case hours = 1
    case days = 2
    case months = 3
    case years = 4
}

struct OverviewSeriesResponse: Decodable {
    let meta: OverviewMetaDto?
    let summary: OverviewSummaryDto?
    let overviewSeriesRows: [OverviewSeriesRowDto]?

    enum CodingKeys: String, CodingKey {
        case meta
        case summary
        case overviewSeriesRows
    }

    init(meta: OverviewMetaDto?, summary: OverviewSummaryDto?, overviewSeriesRows: [OverviewSeriesRowDto]?) {
        self.meta = meta
        self.summary = summary
        self.overviewSeriesRows = overviewSeriesRows
    }
}

struct OverviewSeriesRowDto: Decodable {
    let ts: String
    let activeClients: Int?
    let trafficInBytes: Int64?
    let trafficOutBytes: Int64?
    let trafficTotalBytes: Int64?

    enum CodingKeys: String, CodingKey {
        case ts
        case activeClients
        case trafficInBytes
        case trafficOutBytes
        case trafficTotalBytes
    }
}

struct OverviewMetaDto: Decodable {
    let from: String?
    let to: String?
    let grouping: String?
    let timezone: String?
}

struct OverviewSummaryDto: Decodable {
    let totalTrafficInBytes: Int64?
    let totalTrafficOutBytes: Int64?
    let peakActiveClients: Int?
}

struct OverviewTotalsResponse: Decodable {
    let meta: OverviewMetaDto?
    let totals: TotalsPayloadDto?

    enum CodingKeys: String, CodingKey {
        case meta
        case totals
    }

    init(meta: OverviewMetaDto?, totals: TotalsPayloadDto?) {
        self.meta = meta
        self.totals = totals
    }
}

struct TotalsPayloadDto: Decodable {
    let sessionsCount: Int
    let usersCount: Int
    let trafficInBytes: Int64
    let trafficOutBytes: Int64
    let trafficTotalBytes: Int64?

    enum CodingKeys: String, CodingKey {
        case sessionsCount
        case usersCount
        case trafficInBytes
        case trafficOutBytes
        case trafficTotalBytes
    }

    init(sessionsCount: Int, usersCount: Int, trafficInBytes: Int64, trafficOutBytes: Int64, trafficTotalBytes: Int64?) {
        self.sessionsCount = sessionsCount
        self.usersCount = usersCount
        self.trafficInBytes = trafficInBytes
        self.trafficOutBytes = trafficOutBytes
        self.trafficTotalBytes = trafficTotalBytes ?? trafficInBytes + trafficOutBytes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessionsCount = (try? c.decode(Int.self, forKey: .sessionsCount)) ?? 0
        usersCount = (try? c.decode(Int.self, forKey: .usersCount)) ?? 0
        trafficInBytes = (try? c.decode(Int64.self, forKey: .trafficInBytes)) ?? 0
        trafficOutBytes = (try? c.decode(Int64.self, forKey: .trafficOutBytes)) ?? 0
        let total = try? c.decodeIfPresent(Int64.self, forKey: .trafficTotalBytes)
        trafficTotalBytes = total
    }

    /// Total traffic for quota progress (matches Linux `readOverviewTrafficUsedBytes`).
    var resolvedTrafficBytes: Int64 {
        if let t = trafficTotalBytes, t >= 0 { return t }
        return trafficInBytes + trafficOutBytes
    }
}
