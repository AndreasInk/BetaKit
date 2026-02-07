//
//  PromptHeaderView.swift
//  BetaKit
//
//  Created by Andreas Ink on 2/6/26.
//


import SwiftUI

struct PromptHeaderView: View {
    let title: String
    let subtitle: String?
    var titleFont: Font = .system(size: 32, weight: .heavy, design: .rounded)
    var subtitleFont: Font = .title3
    var titleColor: Color = .primary
    var subtitleColor: Color = .secondary
    var spacing: CGFloat = 12

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            Text(title)
                .font(titleFont)
                .foregroundStyle(titleColor)
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(subtitleFont)
                    .foregroundStyle(subtitleColor)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    PromptHeaderView(title: "Quick question", subtitle: "Where did you find WalkLock?")
        .padding()
}
