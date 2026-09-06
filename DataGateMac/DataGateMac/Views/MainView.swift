//
//  MainView.swift
//  DataGateMac
//
//  Main layout with sidebar navigation (Home, Access, Profiles, Statistics, Settings).
//

import SwiftUI

enum NavItem: String, CaseIterable, Identifiable {
    case home
    case access
    case profiles
    case statistics
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return L10n.tr("nav_home", "Home")
        case .access: return L10n.tr("nav_access", "Access")
        case .profiles: return L10n.tr("nav_profiles", "Profiles")
        case .statistics: return L10n.tr("nav_statistics", "Statistics")
        case .settings: return L10n.tr("nav_settings", "Settings")
        }
    }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .access: return "cable.connector"
        case .profiles: return "list.bullet.rectangle.fill"
        case .statistics: return "chart.bar.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

struct MainView: View {
    @ObservedObject var authState: AuthStateStore
    @StateObject private var vpn: VpnViewModel
    @AppStorage("mainSidebarNavSelection") private var navSelectionRaw: String = NavItem.home.rawValue

    init(authState: AuthStateStore) {
        self.authState = authState
        _vpn = StateObject(wrappedValue: VpnViewModel(authState: authState))
    }

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
                    HStack(alignment: .center, spacing: 10) {
                        UserAvatarView(
                            imageURL: ProfileImageURL.parse(authState.avatarUrl),
                            displayName: authState.displayName,
                            email: authState.email
                        )
                        VStack(alignment: .leading, spacing: 2) {
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
                    }
                    .accessibilityElement(children: .combine)
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
                    HomePageView(authState: authState, vm: vpn)
                case .access:
                    AccessPageView(authState: authState)
                case .profiles:
                    ManualProfilesPageView(vm: vpn)
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
