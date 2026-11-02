import Flutter
import UIKit

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
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    CaptureBridge.shared.appMessenger = engineBridge.applicationRegistrar.messenger()
    LegacyStore.register(with: engineBridge.applicationRegistrar.messenger())
  }
}
