import Flutter
import UIKit
import ObjectiveC

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if #available(iOS 26, *) {
      AppDelegate.swizzleFlutterVSyncClient()
    }
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private static func swizzleFlutterVSyncClient() {
    let originalSel = Selector(("createTouchRateCorrectionVSyncClientIfNeeded"))
    let replacementSel = #selector(FlutterViewController.flutter_noop_vsync)
    guard
      let original = class_getInstanceMethod(FlutterViewController.self, originalSel),
      let replacement = class_getInstanceMethod(FlutterViewController.self, replacementSel)
    else { return }
    method_exchangeImplementations(original, replacement)
  }
}

extension FlutterViewController {
  @objc func flutter_noop_vsync() {
    // Prevents VSyncClient CADisplayLink null-pointer crash on iOS 26 ProMotion displays.
  }
}
