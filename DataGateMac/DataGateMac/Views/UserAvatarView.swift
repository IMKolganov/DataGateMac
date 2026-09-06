//
//  UserAvatarView.swift
//  DataGateMac
//
//  Circular Google profile photo with initials fallback.
//

import SwiftUI

struct UserAvatarView: View {
    let imageURL: URL?
    let displayName: String?
    let email: String?
    var size: CGFloat = 32

    var body: some View {
        Group {
            if let imageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        initialsView
                    }
                }
            } else {
                initialsView
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
        }
        .accessibilityHidden(true)
    }

    private var initialsView: some View {
        ZStack {
            Circle()
                .fill(backgroundTint)
            Text(initials)
                .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
    }

    private var initials: String {
        let name = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let parts = name.split(whereSeparator: { $0.isWhitespace || $0 == "-" })
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        if let first = parts.first, !first.isEmpty {
            return String(first.prefix(1)).uppercased()
        }
        if let mail = email?.trimmingCharacters(in: .whitespacesAndNewlines), let first = mail.first {
            return String(first).uppercased()
        }
        return "?"
    }

    private var backgroundTint: Color {
        let seed = (displayName ?? email ?? "").unicodeScalars.reduce(into: 0) { acc, scalar in
            acc = acc &* 31 &+ Int(scalar.value)
        }
        let hues: [Color] = [
            Color(red: 0.20, green: 0.48, blue: 0.86),
            Color(red: 0.18, green: 0.64, blue: 0.49),
            Color(red: 0.75, green: 0.33, blue: 0.36),
            Color(red: 0.55, green: 0.36, blue: 0.78),
            Color(red: 0.86, green: 0.52, blue: 0.18),
            Color(red: 0.22, green: 0.58, blue: 0.70),
        ]
        let index = abs(seed) % hues.count
        return hues[index]
    }
}
