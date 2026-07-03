import Flutter
import UIKit
import AVFoundation
import ObjectiveC

@main
@objc class AppDelegate: FlutterAppDelegate {
  private lazy var synthesizer = AVSpeechSynthesizer()
  // Explicit engine so registrarForPlugin: works immediately on iOS 26.
  // FlutterAppDelegate.registrarForPlugin: returns nil until a FlutterViewController
  // attaches an engine, which is too late during didFinishLaunchingWithOptions.
  private let engine = FlutterEngine(name: "milometry")

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if #available(iOS 26, *) {
      AppDelegate.swizzleFlutterVSyncClient()
    }
    engine.run()
    GeneratedPluginRegistrant.register(with: engine)

    // Call super for Flutter lifecycle delegate setup.
    // UIMainStoryboardFile is removed from Info.plist so super does not
    // create a storyboard FlutterViewController that would conflict.
    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)

    let flutterVC = FlutterViewController(engine: engine, nibName: nil, bundle: nil)
    window = UIWindow(frame: UIScreen.main.bounds)
    window?.rootViewController = flutterVC
    window?.makeKeyAndVisible()

    setupTtsChannel()
    return result
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

  // Cache the best voice chosen per language so we don't re-scan every utterance.
  private var voiceCache: [String: AVSpeechSynthesisVoice] = [:]

  private func nativeSpeak(text: String, language: String, rate: Float) {
    synthesizer.stopSpeaking(at: .immediate)
    let utterance = AVSpeechUtterance(string: text)
    utterance.voice = bestVoice(for: language)
    utterance.rate = rate
    synthesizer.speak(utterance)
  }

  /// Picks the clearest available voice for a language, preferring premium >
  /// enhanced > default quality. Addresses the "robotic voice" complaint.
  /// Enhanced/premium voices are used automatically when the user has them
  /// installed (Settings > Accessibility > Spoken Content > Voices).
  private func bestVoice(for language: String) -> AVSpeechSynthesisVoice? {
    if let cached = voiceCache[language] { return cached }

    let prefix = String(language.prefix(2)).lowercased()
    let candidates = AVSpeechSynthesisVoice.speechVoices().filter {
      $0.language.lowercased().hasPrefix(prefix)
    }

    let chosen: AVSpeechSynthesisVoice?
    if #available(iOS 16.0, *) {
      chosen = candidates.first(where: { $0.quality == .premium })
        ?? candidates.first(where: { $0.quality == .enhanced })
        ?? candidates.first(where: { $0.quality == .default })
        ?? AVSpeechSynthesisVoice(language: language)
    } else {
      chosen = candidates.first(where: { $0.quality == .enhanced })
        ?? candidates.first(where: { $0.quality == .default })
        ?? AVSpeechSynthesisVoice(language: language)
    }

    if let chosen = chosen { voiceCache[language] = chosen }
    return chosen
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
