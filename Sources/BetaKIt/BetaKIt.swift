import SwiftUI

public extension View {
    func beta(
        viewModel: BetaContentViewModel,
        backgroundMaterial: Material = .thickMaterial,
        foregroundCardStyle: Color = .white,
        screenshotPromptTitle: String = "Want to share quick beta feedback?",
        screenshotPromptSubtitle: String = "Take a screenshot and we’ll guide you from there.",
        triggerAction: (() -> Void)? = nil
    ) -> some View {
        BetaContentView(
            viewModel: viewModel,
            backgroundMaterial: backgroundMaterial,
            foregroundCardStyle: foregroundCardStyle,
            screenshotPromptTitle: screenshotPromptTitle,
            screenshotPromptSubtitle: screenshotPromptSubtitle,
            triggerAction: triggerAction
        ) {
            self
        }
    }
}
