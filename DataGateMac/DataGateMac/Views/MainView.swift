//
//  MainView.swift
//  DataGateMac
//
//  Main layout with sidebar navigation (Home, Access, Statistics, Settings).
//

import SwiftUI

enum NavItem: String, CaseIterable, Identifiable {
    case home
    case access
    case statistics
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return L10n.tr("nav_home", "Home")
        case .access: return L10n.tr("nav_access", "Access")
        case .statistics: return L10n.tr("nav_statistics", "Statistics")
        case .settings: return L10n.tr("nav_settings", "Settings")
        }
    }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .access: return "cable.connector"
        case .statistics: return "chart.bar.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

struct MainView: View {
    @ObservedObject var authState: AuthStateStore
    @AppStorage("mainSidebarNavSelection") private var navSelectionRaw: String = NavItem.home.rawValue

    private var navSelection: Binding<NavItem> {
        Binding(
            get: { NavItem(rawValue: navSelectionRaw) ?? .home },
            set: { navSelectionRaw = $0.rawValue }
        )
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(NavItem.allCases, id: \.self, selection: navSelection) { item in
                    Label(item.title, systemImage: item.icon)
                        .tag(item)
                }
                .listStyle(.sidebar)

                if authState.isAuthorized {
                    VStack(alignment: .leading, spacing: 4) {
                        if let name = authState.displayName, !name.isEmpty {
                            Text(name)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        if let mail = authState.email, !mail.isEmpty {
                            Text(mail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        if authState.displayName == nil && authState.email == nil {
                            Text(L10n.tr("main_logged_in", "Logged in"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.primary.opacity(0.06))
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
        } detail: {
            Group {
                switch NavItem(rawValue: navSelectionRaw) ?? .home {
                case .home:
                    HomePageView(authState: authState)
                case .access:
                    AccessPageView(authState: authState)
                case .statistics:
                    StatisticsPageView(authState: authState)
                case .settings:
                    SettingsPageView(authState: authState)
                }
            }
            .frame(minWidth: 720, minHeight: 400)
        }
    }
}
