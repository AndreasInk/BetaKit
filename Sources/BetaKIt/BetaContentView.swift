//
//  ScreenshotBetaFeedbackView.swift
//  BetaKit
//
//  Created by Andreas Ink on 2/6/26.
//

import SwiftUI

public struct BetaContentView<Content: View>: View {
    
    @Bindable var viewModel: BetaContentViewModel
    
    var backgroundMaterial: Material?
    var backgroundCardView: Content
    var foregroundCardStyle: Color = Color.white
    var screenshotPromptTitle: String
    var screenshotPromptSubtitle: String
    var triggerAction: (() -> Void)?
    
    
    public init(viewModel: BetaContentViewModel,
                backgroundMaterial: Material?,
                foregroundCardStyle: Color = Color.white,
                screenshotPromptTitle: String = "Want to share quick beta feedback?",
                screenshotPromptSubtitle: String = "Take a screenshot and we’ll guide you from there.",
                triggerAction: (() -> Void)? = nil,
                @ViewBuilder background: @escaping () -> Content) {
        self.viewModel = viewModel
        self.backgroundMaterial = backgroundMaterial
        self.triggerAction = triggerAction
        self.foregroundCardStyle = foregroundCardStyle
        self.screenshotPromptTitle = screenshotPromptTitle
        self.screenshotPromptSubtitle = screenshotPromptSubtitle
        self.backgroundCardView = background()
    }
    public var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                Color.clear
                    .ignoresSafeArea()
                if let backgroundMaterial {
                    Rectangle()
                        .foregroundStyle(backgroundMaterial)
                        .ignoresSafeArea()
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(screenshotPromptTitle)
                        .font(.headline)
                    Text(screenshotPromptSubtitle)
                        .font(.callout)
                }
                .foregroundStyle(foregroundCardStyle)
                .minimumScaleFactor(0.3)
                .padding(18)
                .background {
                    backgroundCardView
                }
                .frame(width: geometry.size.width / 3,
                       height: geometry.size.height / 3)
                .padding(.leading, 12)
                .padding(.bottom, geometry.size.height / 3.5)
                .scaleEffect(0.65)
                .blur(radius: viewModel.showScreenshotOverlay ? 0 : 20)
                .offset(x: viewModel.showScreenshotOverlay ? 0 : -100)
            }
            .opacity(viewModel.showScreenshotOverlay ? 1 : 0)
            .sheet(isPresented: $viewModel.showTestFlightFeedbackPrompt) {
                TestFlightFeedbackSheetView()
                    .presentationDetents([.medium])
            }
            .sheet(isPresented: $viewModel.showTestFlightScreenshotTip) {
                TestFlightScreenshotTipView()
                    .presentationDetents([.medium])
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("TestFlightScreenshotTaken"))) { _ in
                guard BetaContentViewModel.isDebugOrTestFlight() else { return }
                withAnimation {
                    viewModel.showScreenshotOverlay = true
                }
                Task {
                    try await Task.sleep(for: .seconds(6))
                    withAnimation {
                        viewModel.showScreenshotOverlay = false
                    }
                }
            }
            .allowsHitTesting(false)
            .environment(viewModel)
        }
    }
}

#Preview {
    @Previewable @State var viewModel = BetaContentViewModel()
    let rect = RoundedRectangle(cornerRadius: 26.0)
    ZStack {
        Color.black.opacity(0.3)
            .ignoresSafeArea()
        
        BetaContentView(
            viewModel: BetaContentViewModel(),
            backgroundMaterial: .thickMaterial,
            foregroundCardStyle: .blue
        ) {
            if #available(iOS 26.0, *) {
                rect
                    .foregroundStyle(.white)
            } else {
                rect
            }
        }
        .environment(viewModel)
    }
}
