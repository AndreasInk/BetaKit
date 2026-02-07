//
//  PromptCardView.swift
//  BetaKit
//
//  Created by Andreas Ink on 2/6/26.
//


import SwiftUI

struct PromptCardView<Content: View>: View {
    struct ShadowStyle {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat

        static var subtle: ShadowStyle {
            ShadowStyle(
                color: Color.black.opacity(0.05),
                radius: 20,
                x: 0,
                y: 12
            )
        }
    }

    private let background: AnyShapeStyle
    private let cornerRadius: CGFloat
    private let shadow: ShadowStyle?
    private let content: Content

    init(
        background: AnyShapeStyle = AnyShapeStyle(.ultraThinMaterial),
        cornerRadius: CGFloat = 32,
        shadow: ShadowStyle? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.background = background
        self.cornerRadius = cornerRadius
        self.shadow = shadow
        self.content = content()
    }

    var body: some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(background)
            )
            .shadow(
                color: shadow?.color ?? .clear,
                radius: shadow?.radius ?? 0,
                x: shadow?.x ?? 0,
                y: shadow?.y ?? 0
            )
    }
}

#Preview {
    PromptCardView {
        Text("Card content")
    }
    .padding()
}
