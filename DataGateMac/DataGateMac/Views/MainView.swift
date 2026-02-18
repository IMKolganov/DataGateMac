//
//  MainView.swift
//  DataGateMac
//
//  Main layout with sidebar navigation (Home, Access, Statistics, Settings).
//

import SwiftUI

enum NavItem: String, CaseIterable {
    case home = "Home"
    case access = "Access"
    case statistics = "Statistics"
    case settings = "Settings"

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
    @State private var selection: NavItem = .home

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(NavItem.allCases, id: \.self, selection: $selection) { item in
                    Label(item.rawValue, systemImage: item.icon)
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
                            Text("Logged in")
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
                switch selection {
                case .home:
                    HomePageView()
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
