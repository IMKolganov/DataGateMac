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
            List(NavItem.allCases, id: \.self, selection: $selection) { item in
                Label(item.rawValue, systemImage: item.icon)
                    .tag(item)
            }
            .listStyle(.sidebar)
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
        }
    }
}
