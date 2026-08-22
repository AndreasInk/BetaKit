#if os(iOS)
import BetaFeedbackKit
import Testing
import UserNotifications

@Suite("Public notification forwarding API")
struct NotificationForwardingPublicAPITests {
    @Test("Consumer apps can compile every documented forwarding helper")
    @MainActor
    func forwardingHelpersArePublic() {
        let viewModel = BetaContentViewModel()

        let presentationHelper: (UNNotification) -> UNNotificationPresentationOptions? =
            viewModel.notificationPresentationOptions(for:)
        let asyncHelper: (UNNotificationResponse) async -> Bool =
            viewModel.handleNotificationResponse(_:)
        let capturedHelper: (BetaFeedbackNotificationResponse) async -> Bool =
            viewModel.handleNotificationResponse(_:)

        _ = presentationHelper
        _ = asyncHelper
        _ = capturedHelper
    }

    private func forwardFromConsumerDelegate(
        _ response: UNNotificationResponse,
        to viewModel: BetaContentViewModel,
        completionHandler: @escaping () -> Void
    ) -> Bool {
        viewModel.handleNotificationResponse(
            response,
            completionHandler: completionHandler
        )
    }
}
#endif
