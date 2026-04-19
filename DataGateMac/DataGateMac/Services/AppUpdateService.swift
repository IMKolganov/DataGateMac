//
//  AppUpdateService.swift
//  DataGateMac
//
//  Checks GitHub Releases for DataGateMac updates.
//

import Foundation

struct AppReleaseInfo: Equatable, Sendable {
    let version: String
    let htmlURL: URL
}

enum AppUpdateCheckResult: Equatable, Sendable {
    case updateAvailable(currentVersion: String, latest: AppReleaseInfo)
    case upToDate(currentVersion: String, latest: AppReleaseInfo?)
    case noReleases(currentVersion: String, releasesPageURL: URL)
    case failed(currentVersion: String, message: String)
}

struct AppUpdateService {
    private struct GitHubReleaseDto: Decodable {
        let tagName: String
        let name: String
        let htmlURL: URL

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case name
            case htmlURL = "html_url"
        }
    }

    let latestReleaseAPIURL = URL(string: "https://api.github.com/repos/IMKolganov/DataGateMac/releases/latest")!
    let releasesPageURL = URL(string: "https://github.com/IMKolganov/DataGateMac/releases")!

    static func currentAppVersion(bundle: Bundle = .main) -> String {
        (bundle.infoDictionary?["CFBundleShortVersionString"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? "1.0"
    }

    func checkForUpdates(currentVersion: String) async -> AppUpdateCheckResult {
        var request = URLRequest(url: latestReleaseAPIURL)
        request.timeoutInterval = 20
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("DataGateMac/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failed(currentVersion: currentVersion, message: L10n.tr("settings_updates_error_bad_response", "GitHub returned an invalid response."))
            }
            if http.statusCode == 404 {
                return .noReleases(currentVersion: currentVersion, releasesPageURL: releasesPageURL)
            }
            guard (200 ... 299).contains(http.statusCode) else {
                let body = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let detail = body?.isEmpty == false ? body! : "HTTP \(http.statusCode)"
                return .failed(
                    currentVersion: currentVersion,
                    message: String(format: L10n.tr("settings_updates_error_http_fmt", "GitHub request failed: %@"), locale: L10n.activeLocaleForFormatting(), detail)
                )
            }

            let release = try JSONDecoder().decode(GitHubReleaseDto.self, from: data)
            let latestVersion = normalizedVersion(from: release.tagName).nilIfEmpty
                ?? normalizedVersion(from: release.name).nilIfEmpty
                ?? release.tagName
            let latest = AppReleaseInfo(version: latestVersion, htmlURL: release.htmlURL)

            if compareVersions(currentVersion, latestVersion) == .orderedAscending {
                return .updateAvailable(currentVersion: currentVersion, latest: latest)
            }
            return .upToDate(currentVersion: currentVersion, latest: latest)
        } catch {
            return .failed(currentVersion: currentVersion, message: error.localizedDescription)
        }
    }

    private func normalizedVersion(from raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^[Vv]"#, with: "", options: .regularExpression)
    }

    private func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let leftParts = versionParts(lhs)
        let rightParts = versionParts(rhs)
        let count = max(leftParts.count, rightParts.count)

        for index in 0 ..< count {
            let l = index < leftParts.count ? leftParts[index] : .number(0)
            let r = index < rightParts.count ? rightParts[index] : .number(0)
            let result = compareVersionPart(l, r)
            if result != .orderedSame {
                return result
            }
        }
        return .orderedSame
    }

    private enum VersionPart: Equatable {
        case number(Int)
        case text(String)
    }

    private func versionParts(_ version: String) -> [VersionPart] {
        version
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map { token in
                if let n = Int(token) {
                    return .number(n)
                }
                return .text(String(token).lowercased())
            }
    }

    private func compareVersionPart(_ lhs: VersionPart, _ rhs: VersionPart) -> ComparisonResult {
        switch (lhs, rhs) {
        case let (.number(a), .number(b)):
            if a < b { return .orderedAscending }
            if a > b { return .orderedDescending }
            return .orderedSame
        case let (.text(a), .text(b)):
            return a.compare(b, options: [.caseInsensitive, .numeric])
        case (.number, .text):
            return .orderedDescending
        case (.text, .number):
            return .orderedAscending
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
