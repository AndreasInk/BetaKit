//
//  BetaButtonStyle.swift
//  BetaKit
//
//  Created by Andreas Ink on 2/6/26.
//


import SwiftUI

struct BetaButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.accentColor,
                                Color.accentColor.opacity(0.85)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .foregroundStyle(.white)
            .opacity(opacity(configuration: configuration))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: configuration.isPressed)
    }

    private func opacity(configuration: Configuration) -> Double {
        guard isEnabled else { return 0.45 }
        return configuration.isPressed ? 0.85 : 1.0
    }
}

extension Button where Label == Text {
    func onboardingButtonStyle() -> some View {
        self.buttonStyle(BetaButtonStyle())
    }
}
