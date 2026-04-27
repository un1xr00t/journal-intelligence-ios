import CarPlay
import UIKit

@available(iOS 13.0, *)
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
  private static let launchRouteActivityType =
    "name.williamthomas.journalIntelligence.route"
  private static let launchRouteUserInfoKey = "route"
  private weak var interfaceController: CPInterfaceController?
  private weak var templateScene: CPTemplateApplicationScene?

  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didConnect interfaceController: CPInterfaceController,
    to window: CPWindow
  ) {
    self.interfaceController = interfaceController
    self.templateScene = templateApplicationScene
    interfaceController.setRootTemplate(makeRootTemplate(), animated: true)
  }

  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didDisconnectInterfaceController interfaceController: CPInterfaceController,
    from window: CPWindow
  ) {
    if self.interfaceController === interfaceController {
      self.interfaceController = nil
      self.templateScene = nil
    }
  }

  private func makeRootTemplate() -> CPGridTemplate {
    let buttons = [
      makeButton(
        title: "Companion",
        systemImage: "rectangle.on.rectangle.circle.fill",
        route: "/carplay"
      ),
      makeButton(
        title: "Voice Entry",
        systemImage: "waveform.circle.fill",
        route: "/carplay?focus=voice"
      ),
      makeButton(
        title: "Briefing",
        systemImage: "play.circle.fill",
        route: "/carplay?focus=briefing"
      ),
      makeButton(
        title: "Today",
        systemImage: "sparkles",
        route: "/today"
      ),
      makeButton(
        title: "Ask Sage",
        systemImage: "brain.head.profile",
        route: "/sage"
      ),
      makeButton(
        title: "Detective",
        systemImage: "folder.badge.questionmark",
        route: "/detective"
      ),
    ]

    return CPGridTemplate(
      title: "Journal Intelligence",
      gridButtons: buttons
    )
  }

  private func makeButton(
    title: String,
    systemImage: String,
    route: String
  ) -> CPGridButton {
    let image = UIImage(systemName: systemImage) ?? UIImage()
    return CPGridButton(titleVariants: [title], image: image) { [weak self] _ in
      self?.openRoute(route)
    }
  }

  private func openRoute(_ route: String) {
    let userActivity = NSUserActivity(activityType: Self.launchRouteActivityType)
    userActivity.title = "Open Journal Route"
    userActivity.userInfo = [Self.launchRouteUserInfoKey: route]
    userActivity.targetContentIdentifier = route

    let options = UIScene.ActivationRequestOptions()
    options.requestingScene = templateScene

    let targetSession = UIApplication.shared.connectedScenes
      .first(where: { $0.session.role == .windowApplication })?.session

    UIApplication.shared.requestSceneSessionActivation(
      targetSession,
      userActivity: userActivity,
      options: options
    ) { [weak self] _ in
      self?.openRouteFallback(route)
    }
  }

  private func openRouteFallback(_ route: String) {
    guard let url = URL(string: "journalintelligence://\(route)") else { return }
    UIApplication.shared.open(url, options: [:], completionHandler: nil)
  }
}
