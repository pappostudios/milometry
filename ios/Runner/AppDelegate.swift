import Flutter
import UIKit
import AVFoundation
import ObjectiveC

@main
@objc class AppDelegate: FlutterAppDelegate {
  private lazy var synthesizer = AVSpeechSynthesizer()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if #available(iOS 26, *) {
      AppDelegate.swizzleFlutterVSyncClient()
    }
    GeneratedPluginRegistrant.register(with: self)
    let launched = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    setupTtsChannel()
    return launched
  }

  private func setupTtsChannel() {
    guard let controller = window?.rootViewController as? FlutterViewController else { return }
    FlutterMethodChannel(
      name: "com.pappostudios.milometry/tts",
      binaryMessenger: controller.binaryMessenger
    ).setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "speak":
        guard let args = call.arguments as? [String: Any],
              let text = args["text"] as? String,
              let lang = args["language"] as? String
        else { result(FlutterError(code: "ARGS", message: nil, details: nil)); return }
        let rate = (args["rate"] as? Double).map { Float($0) }
          ?? AVSpeechUtteranceDefaultSpeechRate
        self?.nativeSpeak(text: text, language: lang, rate: rate)
        result(nil)
      case "stop":
        self?.synthesizer.stopSpeaking(at: .immediate)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func nativeSpeak(text: String, language: String, rate: Float) {
    synthesizer.stopSpeaking(at: .immediate)
    let utterance = AVSpeechUtterance(string: text)
    utterance.voice = AVSpeechSynthesisVoice(language: language)
    utterance.rate = rate
    synthesizer.speak(utterance)
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
