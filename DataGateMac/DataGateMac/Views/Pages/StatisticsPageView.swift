//
//  StatisticsPageView.swift
//  DataGateMac
//

import SwiftUI

struct StatisticsPageView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Statistics")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Connection and usage statistics.")
                    .foregroundStyle(.secondary)
                Text("Coming soon.")
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 400, minHeight: 300)
    }
}
