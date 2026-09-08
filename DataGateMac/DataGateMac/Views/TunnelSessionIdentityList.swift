//
//  TunnelSessionIdentityList.swift
//  DataGateMac
//
//  Labeled rows for the connected server / protocol / address / CN / file.
//

import SwiftUI

struct TunnelSessionIdentityList: View {
    let rows: [TunnelSessionIdentityRow]

    var body: some View {
        if !rows.isEmpty {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 6) {
                ForEach(rows) { row in
                    GridRow {
                        Text(row.label)
                            .foregroundStyle(.secondary)
                            .gridColumnAlignment(.trailing)
                        Text(row.value)
                            .font(row.usesMonospace ? .system(.callout, design: .monospaced) : .callout)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .font(.callout)
        }
    }
}
