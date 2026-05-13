import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    // After super, FlutterViewController is the root view controller.
    // Use its binaryMessenger — the only reliable source with scene-based lifecycle
    // (AppDelegate.window is nil so window?.rootViewController never works).
    guard
      let windowScene = scene as? UIWindowScene,
      let controller  = windowScene.windows.first?.rootViewController as? FlutterViewController,
      let appDelegate = UIApplication.shared.delegate as? AppDelegate
    else { return }
    appDelegate.setupChannels(messenger: controller.binaryMessenger)
  }
}
