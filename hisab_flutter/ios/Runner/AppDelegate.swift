import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    #if DEBUG
    // Simulator check of the Shortcuts path without Shortcuts. It WRITES a
    // memo, so never pass it to a build on a real phone with real data.
    if ProcessInfo.processInfo.arguments.contains("--capture-selftest") {
      Task { @MainActor in
        let dialog = await CaptureBridge.shared.ingest(
          text: "Rs.450.00 debited from a/c XX1234 on 22-09-26 to VPA vedant@okaxis. UPI Ref No 627775786529",
          note: "selftest")
        print("CAPTURE-SELFTEST \(dialog)")
      }
    }
    #endif
    // flutter_local_notifications forwards banners and taps through the app
    // delegate; without this, foreground banners never show and taps are lost.
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    CaptureBridge.shared.appMessenger = engineBridge.applicationRegistrar.messenger()
    LegacyStore.register(with: engineBridge.applicationRegistrar.messenger())
    CaptureCategories.register(with: engineBridge.applicationRegistrar.messenger())
    PdfKitText.register(with: engineBridge.applicationRegistrar.messenger())
    AppleModelChannel.register(with: engineBridge.applicationRegistrar.messenger())
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "HisabIncomingRouter") {
      IncomingRouter.shared.attach(to: registrar)
    }
  }
}
