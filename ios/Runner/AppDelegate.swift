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
              let ns = error as NSError
              let msg = "stage=\(Wav16kConverter.lastStage) type=\(type(of: error)) domain=\(ns.domain) code=\(ns.code) desc=\(ns.localizedDescription)"
              Wav16kConverter.log("ERROR " + msg)
              DispatchQueue.main.async {
                result(["success": false, "error": msg])
              }
            }
          }
        default:
          result(FlutterMethodNotImplemented)
        }
      }

      FlutterMethodChannel(name: "dictapro/model", binaryMessenger: messenger).setMethodCallHandler { call, result in
        if call.method == "getGigaamModelPath" {
          result(nil)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }

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

/// Decodes any audio file readable by AVFoundation and writes a plain
/// 16 kHz mono 16-bit PCM WAV. No AVAudioConverter is used: decoding plus
/// linear resampling plus a hand-written RIFF header keeps this deterministic.
enum Wav16kConverter {
  static let targetRate: Double = 16000
  static var lastStage = "init"

  static func logPath() -> String {
    let dir = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
    return dir + "/dictapro_convert.log"
  }

  static func log(_ line: String) {
    let path = logPath()
    let stamp = ISO8601DateFormatter().string(from: Date())
    let text = stamp + " " + line + "\n"
    if let h = FileHandle(forWritingAtPath: path) {
      h.seekToEndOfFile()
      if let d = text.data(using: .utf8) { h.write(d) }
      h.closeFile()
    } else {
      try? text.write(toFile: path, atomically: true, encoding: .utf8)
    }
  }

  static func convert(inputPath: String, outputPath: String) throws {
    lastStage = "open_source"
    log("start input=\(inputPath) output=\(outputPath)")
    let src = try AVAudioFile(forReading: URL(fileURLWithPath: inputPath))
    let fmt = src.processingFormat
    let srcRate = fmt.sampleRate
    let srcCh = Int(fmt.channelCount)
    guard srcRate > 0, srcCh > 0 else {
      throw NSError(domain: "dictapro", code: 10, userInfo: [NSLocalizedDescriptionKey: "unreadable source format"])
    }

    let fm = FileManager.default
    try? fm.removeItem(atPath: outputPath)
    fm.createFile(atPath: outputPath, contents: nil)
    guard let out = FileHandle(forWritingAtPath: outputPath) else {
      throw NSError(domain: "dictapro", code: 11, userInfo: [NSLocalizedDescriptionKey: "cannot open output file"])
    }
    out.write(Data(count: 44))

    lastStage = "prepare"
    log("source rate=\(srcRate) ch=\(srcCh)")
    let step = srcRate / targetRate
    let chunkFrames: AVAudioFrameCount = 32768
    var pos: Double = 0
    var base: Double = 0
    var pending = Data()
    var dataBytes: UInt32 = 0

    while true {
      guard let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: chunkFrames) else { break }
      try src.read(into: buf)
      let n = Int(buf.frameLength)
      if n == 0 { break }
      guard let chData = buf.floatChannelData else { break }

      var i0 = Int(floor(pos - base))
      while Double(i0) + 1.0 < Double(n) {
        let t = Float(pos - base - Double(i0))
        var acc: Float = 0
        for c in 0..<srcCh {
          let s = chData[c]
          acc += s[i0] * (1 - t) + s[i0 + 1] * t
        }
        acc /= Float(srcCh)
        let clipped = max(-1.0, min(1.0, acc))
        var v = Int16(clipped * 32767.0).littleEndian
        withUnsafeBytes(of: &v) { pending.append(contentsOf: $0) }
        pos += step
        i0 = Int(floor(pos - base))
      }

      if pending.count >= 1 << 20 {
        out.write(pending)
        dataBytes &+= UInt32(pending.count)
        pending.removeAll(keepingCapacity: true)
      }
      base += Double(n)
    }

    if !pending.isEmpty {
      out.write(pending)
      dataBytes &+= UInt32(pending.count)
    }

    lastStage = "write_header"
    log("pcm bytes=\(dataBytes)")
    // RIFF / WAVE header for mono 16-bit PCM.
    var header = Data()
    func append32(_ v: UInt32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { header.append(contentsOf: $0) } }
    func append16(_ v: UInt16) { var x = v.littleEndian; withUnsafeBytes(of: &x) { header.append(contentsOf: $0) } }
    let byteRate = UInt32(targetRate) * 2
    header.append(contentsOf: Array("RIFF".utf8))
    append32(36 &+ dataBytes)
    header.append(contentsOf: Array("WAVE".utf8))
    header.append(contentsOf: Array("fmt ".utf8))
    append32(16)
    append16(1)
    append16(1)
    append32(UInt32(targetRate))
    append32(byteRate)
    append16(2)
    append16(16)
    header.append(contentsOf: Array("data".utf8))
    append32(dataBytes)

    lastStage = "done"
    log("finished output=\(outputPath)")
    out.seek(toFileOffset: 0)
    out.write(header)
    out.closeFile()
  }
}
