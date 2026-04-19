//
//  QuotaModels.swift
//  DataGateMac
//
//  DTOs for quota plan APIs (aligned with Android QuotaPlanApi / AccessRepositoryImpl).
//

import Foundation

// MARK: - API envelopes

struct QuotaPlansGetAllData: Decodable {
    let quotaPlans: [QuotaPlanDto]

    enum CodingKeys: String, CodingKey {
        case quotaPlans
        case quotaPlansPascal = "QuotaPlans"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let list = try? c.decode([QuotaPlanDto].self, forKey: .quotaPlans) {
            quotaPlans = list
        } else {
            quotaPlans = (try? c.decode([QuotaPlanDto].self, forKey: .quotaPlansPascal)) ?? []
        }
    }
}

struct UserQuotaPlansByUserData: Decodable {
    let items: [UserQuotaPlanDto]

    enum CodingKeys: String, CodingKey {
        case items
        case itemsPascal = "Items"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let list = try? c.decode([UserQuotaPlanDto].self, forKey: .items) {
            items = list
        } else {
            items = (try? c.decode([UserQuotaPlanDto].self, forKey: .itemsPascal)) ?? []
        }
    }
}

struct QuotaPlanDto: Decodable, Identifiable {
    let id: Int
    let name: String
    let description: String?
    let isActive: Bool
    let isDefault: Bool
    /// Traffic limit for the current calendar month (Linux `monthlyQuotaBytes`).
    let monthlyQuotaBytes: Int64
    /// Traffic limit for the current local day (Linux `dailyQuotaBytes`).
    let dailyQuotaBytes: Int64

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case isActive
        case isDefault
        case monthlyQuotaBytes
        case monthlyQuotaBytesPascal = "MonthlyQuotaBytes"
        case dailyQuotaBytes
        case dailyQuotaBytesPascal = "DailyQuotaBytes"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        description = try? c.decodeIfPresent(String.self, forKey: .description)
        isActive = (try? c.decode(Bool.self, forKey: .isActive)) ?? true
        isDefault = (try? c.decode(Bool.self, forKey: .isDefault)) ?? false
        monthlyQuotaBytes = Self.decodeFlexInt64(c, camel: .monthlyQuotaBytes, pascal: .monthlyQuotaBytesPascal)
        dailyQuotaBytes = Self.decodeFlexInt64(c, camel: .dailyQuotaBytes, pascal: .dailyQuotaBytesPascal)
    }

    private static func decodeFlexInt64(_ c: KeyedDecodingContainer<CodingKeys>, camel: CodingKeys, pascal: CodingKeys) -> Int64 {
        if let d = try? c.decodeIfPresent(Double.self, forKey: camel) { return Int64(d) }
        if let d = try? c.decodeIfPresent(Double.self, forKey: pascal) { return Int64(d) }
        if let i = try? c.decodeIfPresent(Int64.self, forKey: camel) { return i }
        if let i = try? c.decodeIfPresent(Int64.self, forKey: pascal) { return i }
        return 0
    }
}

struct UserQuotaPlanDto: Decodable {
    let id: Int
    let userId: Int
    let quotaPlanId: Int
    let effectiveFrom: String?
    let effectiveTo: String?
    let assignedBy: Int?
    let note: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId
        case quotaPlanId
        case effectiveFrom
        case effectiveTo
        case assignedBy
        case note
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        userId = (try? c.decode(Int.self, forKey: .userId)) ?? 0
        quotaPlanId = (try? c.decode(Int.self, forKey: .quotaPlanId)) ?? 0
        effectiveFrom = try? c.decodeIfPresent(String.self, forKey: .effectiveFrom)
        effectiveTo = try? c.decodeIfPresent(String.self, forKey: .effectiveTo)
        assignedBy = try? c.decodeIfPresent(Int.self, forKey: .assignedBy)
        note = try? c.decodeIfPresent(String.self, forKey: .note)
    }
}

// MARK: - UI state (Access page)

struct QuotaPlanRow: Identifiable, Equatable {
    let id: Int
    let name: String
    let description: String?
    let isActive: Bool
    let isDefault: Bool
}

struct QuotaSectionState: Equatable {
    var errorText: String?
    var currentPlanName: String?
    var currentEffectiveFrom: String?
    var currentNote: String?
    var allPlans: [QuotaPlanRow] = []
    /// When set, replaces the traffic progress bar (Linux-style messages).
    var trafficQuotaHelpText: String?
    var trafficUsedBytes: Int64?
    var trafficLimitBytes: Int64 = 0
    var trafficPeriodIsMonthly: Bool = false

    static let empty = QuotaSectionState()

    /// Mirrors Android `AccessRepositoryImpl.loadQuotaUi` + `pickActiveAssignment`.
    static func build(
        plansSuccess: Bool,
        plansMessage: String,
        userSuccess: Bool,
        userMessage: String,
        plans: [QuotaPlanDto],
        assignments: [UserQuotaPlanDto]
    ) -> QuotaSectionState {
        if !plansSuccess {
            return QuotaSectionState(
                errorText: plansMessage.isEmpty ? L10n.tr("quota_plans_failed", "Quota plans request failed") : plansMessage
            )
        }
        if !userSuccess {
            return QuotaSectionState(
                errorText: userMessage.isEmpty ? L10n.tr("quota_user_plans_failed", "User quota plans request failed") : userMessage
            )
        }

        let active = pickActiveAssignment(assignments)
        let planName: String? = active.map { a in
            if let p = plans.first(where: { $0.id == a.quotaPlanId }), !p.name.isEmpty {
                return p.name
            }
            return String(
                format: L10n.tr("quota_plan_numbered_fmt", "Quota plan #%d"),
                locale: L10n.activeLocaleForFormatting(),
                a.quotaPlanId
            )
        }

        let rows = plans.map { p in
            QuotaPlanRow(
                id: p.id,
                name: p.name.isEmpty ? L10n.tr("quota_name_empty", "—") : p.name,
                description: p.description,
                isActive: p.isActive,
                isDefault: p.isDefault
            )
        }
        .sorted {
            if $0.isDefault != $1.isDefault { return $0.isDefault && !$1.isDefault }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        return QuotaSectionState(
            errorText: nil,
            currentPlanName: planName,
            currentEffectiveFrom: active?.effectiveFrom,
            currentNote: active?.note,
            allPlans: rows,
            trafficQuotaHelpText: nil,
            trafficUsedBytes: nil,
            trafficLimitBytes: 0,
            trafficPeriodIsMonthly: false
        )
    }

    /// Open-ended assignment (`effectiveTo` blank), then latest `effectiveFrom` (Android).
    static func pickActiveAssignment(_ items: [UserQuotaPlanDto]) -> UserQuotaPlanDto? {
        if items.isEmpty { return nil }
        let openEnded = items.filter { ($0.effectiveTo ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let pool = openEnded.isEmpty ? items : openEnded
        return pool.max {
            let a = $0.effectiveFrom ?? ""
            let b = $1.effectiveFrom ?? ""
            if a != b { return a < b }
            return $0.id < $1.id
        }
    }

    /// Fills `trafficUsedBytes` / limits via `overview/summary` (same flow as DataGateLinux `fetchUserVpnAccessInfoSync`).
    func withOverviewTraffic(token: String, plans: [QuotaPlanDto], assignments: [UserQuotaPlanDto]) async -> QuotaSectionState {
        var s = self
        guard s.errorText == nil else { return s }
        guard let active = Self.pickActiveAssignment(assignments) else { return s }
        guard let plan = plans.first(where: { $0.id == active.quotaPlanId }) else { return s }

        let monthly = plan.monthlyQuotaBytes
        let daily = plan.dailyQuotaBytes
        let limit: Int64
        let isMonthly: Bool
        if monthly > 0 {
            limit = monthly
            isMonthly = true
        } else if daily > 0 {
            limit = daily
            isMonthly = false
        } else {
            s.trafficQuotaHelpText = L10n.tr(
                "access_quota_no_traffic_limit",
                "No daily or monthly traffic limit is configured on the active quota plan."
            )
            s.trafficUsedBytes = nil
            s.trafficLimitBytes = 0
            return s
        }

        let ext = JwtClaimReader.getExternalId(fromJwt: token)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if ext.isEmpty {
            s.trafficQuotaHelpText = L10n.tr(
                "access_quota_needs_external_id",
                "Traffic usage needs an OpenVPN client ID (external ID) on your account."
            )
            s.trafficUsedBytes = nil
            s.trafficLimitBytes = limit
            s.trafficPeriodIsMonthly = isMonthly
            return s
        }

        let (from, to) = Self.overviewPeriodLocalBounds(isMonthly: isMonthly)
        do {
            let summary = try await StatisticsApiClient.shared.getOverviewSummary(
                token: token,
                from: from,
                to: to,
                vpnServerId: nil,
                externalId: ext
            )
            guard let totals = summary.totals else {
                s.trafficQuotaHelpText = L10n.tr("access_quota_usage_unavailable", "Usage data unavailable.")
                s.trafficUsedBytes = nil
                s.trafficLimitBytes = limit
                s.trafficPeriodIsMonthly = isMonthly
                return s
            }
            let used = totals.resolvedTrafficBytes
            s.trafficUsedBytes = used
            s.trafficLimitBytes = limit
            s.trafficPeriodIsMonthly = isMonthly
            s.trafficQuotaHelpText = nil
        } catch {
            s.trafficQuotaHelpText = L10n.tr("access_quota_usage_unavailable", "Usage data unavailable.")
            s.trafficUsedBytes = nil
            s.trafficLimitBytes = limit
            s.trafficPeriodIsMonthly = isMonthly
        }
        return s
    }

    private static func overviewPeriodLocalBounds(isMonthly: Bool) -> (Date, Date) {
        let cal = Calendar.current
        let now = Date()
        let tz = TimeZone.current
        if isMonthly {
            var c = cal.dateComponents(in: tz, from: now)
            c.day = 1
            c.hour = 0
            c.minute = 0
            c.second = 0
            c.nanosecond = 0
            guard let monthStart = cal.date(from: c) else { return (now, now) }
            guard let range = cal.range(of: .day, in: .month, for: monthStart),
                  let lastDay = cal.date(byAdding: .day, value: range.count - 1, to: monthStart) else {
                return (monthStart, now)
            }
            var endC = cal.dateComponents(in: tz, from: lastDay)
            endC.hour = 23
            endC.minute = 59
            endC.second = 59
            endC.nanosecond = 999_000_000
            let monthEnd = cal.date(from: endC) ?? lastDay
            return (monthStart, monthEnd)
        }
        var startC = cal.dateComponents(in: tz, from: now)
        startC.hour = 0
        startC.minute = 0
        startC.second = 0
        startC.nanosecond = 0
        guard let dayStart = cal.date(from: startC) else { return (now, now) }
        var endC = startC
        endC.hour = 23
        endC.minute = 59
        endC.second = 59
        endC.nanosecond = 999_000_000
        let dayEnd = cal.date(from: endC) ?? dayStart
        return (dayStart, dayEnd)
    }
}

// MARK: - Effective-from display (Android `formatQuotaEffectiveFromForDisplay`)

enum QuotaEffectiveFromDisplay {
    static func format(_ raw: String) -> String {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return s }

        if let ymd = matchYmdOnly(s) ?? matchMidnightIso(s) {
            return formatYmdMedium(ymd) ?? s
        }
        if let formatted = tryParseIsoDateTime(s) {
            return formatted
        }
        return s
    }

    private static func matchYmdOnly(_ s: String) -> String? {
        let pattern = #"^(\d{4}-\d{2}-\d{2})$"#
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              m.numberOfRanges >= 2,
              let r = Range(m.range(at: 1), in: s) else { return nil }
        return String(s[r])
    }

    private static func matchMidnightIso(_ s: String) -> String? {
        let pattern = #"^(\d{4}-\d{2}-\d{2})T00:00:00(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$"#
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              m.numberOfRanges >= 2,
              let r = Range(m.range(at: 1), in: s) else { return nil }
        return String(s[r])
    }

    private static func formatYmdMedium(_ ymd: String) -> String? {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone.current
        df.dateFormat = "yyyy-MM-dd"
        guard let date = df.date(from: ymd) else { return nil }
        let out = DateFormatter()
        out.dateStyle = .medium
        out.timeStyle = .none
        out.locale = L10n.activeLocaleForFormatting()
        return out.string(from: date)
    }

    private static func tryParseIsoDateTime(_ s: String) -> String? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) {
            return formatMediumDateShortTime(d)
        }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s) {
            return formatMediumDateShortTime(d)
        }
        return nil
    }

    private static func formatMediumDateShortTime(_ date: Date) -> String {
        let df = DateFormatter()
        df.locale = L10n.activeLocaleForFormatting()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df.string(from: date)
    }
}
