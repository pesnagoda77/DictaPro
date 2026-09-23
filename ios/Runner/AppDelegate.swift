import Flutter
import UIKit
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    if let controller = window?.rootViewController as? FlutterViewController {
      let messenger = controller.binaryMessenger

      // 1) Audio -> 16 kHz mono WAV (same contract as Android MainActivity 'dictapro/convert').
      FlutterMethodChannel(name: "dictapro/convert", binaryMessenger: messenger).setMethodCallHandler { call, result in
        switch call.method {
        case "convertToWav":
          let args = call.arguments as? [String: Any]
          guard let input = args?["inputPath"] as? String,
                let output = args?["outputPath"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "inputPath or outputPath is null", details: nil))
            return
          }
          DispatchQueue.global(qos: .userInitiated).async {
            do {
              try Wav16kConverter.convert(inputPath: input, outputPath: output)
              DispatchQueue.main.async { result(["success": true]) }
            } catch {
              DispatchQueue.main.async { result(["success": false, "error": error.localizedDescription]) }
            }
          }
        default:
          result(FlutterMethodNotImplemented)
        }
      }

      // 2) Model channel: on iOS the GigaAM model ships inside the app bundle
      //    (flutter assets) and Dart copies it from there, so no native path is needed.
      FlutterMethodChannel(name: "dictapro/model", binaryMessenger: messenger).setMethodCallHandler { call, result in
        if call.method == "getGigaamModelPath" {
          result(nil)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }

      // 3) Keep-alive channel: Android-only battery helpers. On iOS report "unknown"
      //    and route settings requests to the app's own settings page.
      FlutterMethodChannel(name: "dictapro/keepalive", binaryMessenger: messenger).setMethodCallHandler { call, result in
        switch call.method {
        case "batteryUnrestrictedStatus":
          result(nil)
        case "openBatterySettings":
          if let url = URL(string: UIApplication.openSettingsURLString) {
            DispatchQueue.main.async { UIApplication.shared.open(url, options: [:], completionHandler: nil) }
            result(true)
          } else {
            result(false)
          }
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

enum Wav16kConverter {
  static func convert(inputPath: String, outputPath: String,
                      sampleRate: Double = 16000, channels: AVAudioChannelCount = 1) throws {
    let inURL = URL(fileURLWithPath: inputPath)
    let outURL = URL(fileURLWithPath: outputPath)

    let srcFile = try AVAudioFile(forReading: inURL)
    let srcFormat = srcFile.processingFormat

    guard let outFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                        sampleRate: sampleRate,
                                        channels: channels,
                                        interleaved: true) else {
      throw NSError(domain: "dictapro", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "cannot create output format"])
    }
    guard let converter = AVAudioConverter(from: srcFormat, to: outFormat) else {
      throw NSError(domain: "dictapro", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "cannot create audio converter"])
    }

    try? FileManager.default.removeItem(at: outURL)
    let outFile = try AVAudioFile(forWriting: outURL,
                                  settings: outFormat.settings,
                                  commonFormat: .pcmFormatInt16,
                                  interleaved: true)

    let inCapacity: AVAudioFrameCount = 16384
    let ratio = outFormat.sampleRate / srcFormat.sampleRate

    while true {
      guard let inBuf = AVAudioPCMBuffer(pcmFormat: srcFormat, frameCapacity: inCapacity) else { break }
      try srcFile.read(into: inBuf)
      if inBuf.frameLength == 0 { break }

      let outCapacity = AVAudioFrameCount(Double(inBuf.frameLength) * ratio + 1024)
      guard let outBuf = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: outCapacity) else { break }

      var err: NSError?
      var supplied = false
      let status = converter.convert(to: outBuf, error: &err) { _, outStatus in
        if supplied {
          outStatus.pointee = .noDataNow
          return nil
        }
        supplied = true
        outStatus.pointee = .haveData
        return inBuf
      }
      if status == .error {
        throw err ?? NSError(domain: "dictapro", code: 3,
                             userInfo: [NSLocalizedDescriptionKey: "conversion error"])
      }
      if status == .endOfStream { break }
      if outBuf.frameLength > 0 { try outFile.write(from: outBuf) }
    }
  }
}
