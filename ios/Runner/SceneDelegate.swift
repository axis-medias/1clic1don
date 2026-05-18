// ios/Runner/SceneDelegate.swift
import UIKit
import Flutter

@available(iOS 13.0, *)
@objcMembers
class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        // CRÉE LE FlutterViewController
        let flutterViewController = FlutterViewController()

        // Configure la fenêtre
        window = UIWindow(windowScene: windowScene)
        window?.rootViewController = flutterViewController
        window?.makeKeyAndVisible()
        print("✅ SceneDelegate loaded and FlutterViewController initialized")

        // ENREGISTRE LES PLUGINS
        GeneratedPluginRegistrant.register(with: flutterViewController.engine)
    }

    // AUTRES MÉTHODES (facultatives, mais bonnes pratiques)
    func sceneDidDisconnect(_ scene: UIScene) {}
    func sceneDidBecomeActive(_ scene: UIScene) {}
    func sceneWillResignActive(_ scene: UIScene) {}
    func sceneWillEnterForeground(_ scene: UIScene) {}
    func sceneDidEnterBackground(_ scene: UIScene) {}
}