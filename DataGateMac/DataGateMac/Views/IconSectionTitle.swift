//
//  IconSectionTitle.swift
//  DataGateMac
//

import SwiftUI

struct IconSectionTitle: View {
    let title: String
    let systemImage: String
    var style: Style = .section

    enum Style {
        case page
        case section
    }

    var body: some View {
        Label {
            Text(title)
                .font(style == .page ? .title2 : .headline)
                .fontWeight(.semibold)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(.tint)
                .imageScale(style == .page ? .large : .medium)
        }
        .labelStyle(.titleAndIcon)
    }
}
