import Flutter
import UIKit
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var silencePlayer: AVAudioPlayer?
  private var silencePath: String?
  private var bgTaskId: UIBackgroundTaskIdentifier = .invalid
  private var bgChannel: FlutterMethodChannel?
  private var watchdog: Timer?
  private var bgRenewCount = 0

  /// Лог фонового режима в Documents — читается с телефона для диагностики.
  private func bgLog(_ s: String) {
    let dir = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
    let path = dir + "/dictapro_bg.log"
    let line = ISO8601DateFormatter().string(from: Date()) + " " + s + "\n"
    if let h = FileHandle(forWritingAtPath: path) {
      h.seekToEndOfFile()
      if let d = line.data(using: .utf8) { h.write(d) }
      h.closeFile()
    } else {
      try? line.write(toFile: path, atomically: true, encoding: .utf8)
    }
  }

  /// Сторож: раз в 20 с продлевает background task и поднимает тишину,
  /// если iOS её приостановила (иначе процесс засыпает и расшифровка «вылетает»).
  private func startWatchdog() {
    watchdog?.invalidate()
    watchdog = Timer.scheduledTimer(withTimeInterval: 20.0, repeats: true) { [weak self] _ in
      guard let self else { return }
      self.endTask()
      self.beginTask()
      self.bgRenewCount += 1
      if self.silencePlayer?.isPlaying != true {
        self.bgLog("watchdog: тишина не играет -> перезапуск")
        self.silencePlayer = nil
        self.startSilence()
      } else if self.bgRenewCount % 15 == 0 {
        self.bgLog("watchdog: живой, продлений=\(self.bgRenewCount)")
      }
    }
  }
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    // Аудиосессия в фоновом режиме: playback + смешивание с другими
    // (музыка пользователя не прерывается, но сессия остаётся «живой»).
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, options: [.mixWithOthers])
      try session.setActive(true)
    } catch {
      NSLog("[iosbg] audio session: \(error.localizedDescription)")
    }

    // Возобновляем тишину после прерываний (звонок/Siri), иначе фон сдохнет
    // незаметно для Dart-стороны.
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(onAudioInterruption(_:)),
      name: AVAudioSession.interruptionNotification,
      object: nil
    )


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

    let ok = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    guard let messenger = (window?.rootViewController as? FlutterViewController)?.binaryMessenger else {
      NSLog("[iosbg] rootViewController ещё не готов — канал не поднят")
      return ok
    }
    bgChannel = FlutterMethodChannel(name: "dictapro/iosbg", binaryMessenger: messenger)
    bgChannel?.setMethodCallHandler { [weak self] call, result in
      guard let self else { result(false); return }
      switch call.method {
      case "startSilence":
        self.startSilence()
        result(true)
      case "stopSilence":
        self.stopSilence()
        result(true)
      case "beginTask":
        self.beginTask()
        result(true)
      case "endTask":
        self.endTask()
        result(true)
      // Task 060: пока идёт расшифровка, экран не гаснет — иначе iOS
      // приостанавливает приложение за высокую нагрузку CPU в фоне.
      case "keepScreenOn":
        DispatchQueue.main.async { UIApplication.shared.isIdleTimerDisabled = true }
        result(true)
      case "allowSleep":
        DispatchQueue.main.async { UIApplication.shared.isIdleTimerDisabled = false }
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    return ok
  }
  /// WAV из нулей (1 с, 16 кГц моно) — файл нужен AVAudioPlayer'у.
  /// Пишется один раз во временную папку.
  private func ensureSilenceFile() -> String? {
    if let p = silencePath, FileManager.default.fileExists(atPath: p) { return p }
    let p = NSTemporaryDirectory() + "dictapro_silence.wav"
    let sampleRate: Int = 16000
    let dataSize = sampleRate * 2 // 1 с * 16 бит
    var wav = Data()
    func le32(_ v: Int) { for i in 0..<4 { wav.append(UInt8((v >> (8 * i)) & 0xff)) } }
    func le16(_ v: Int) { for i in 0..<2 { wav.append(UInt8((v >> (8 * i)) & 0xff)) } }
    wav.append("RIFF".data(using: .ascii)!)
    le32(36 + dataSize)
    wav.append("WAVE".data(using: .ascii)!)
    wav.append("fmt ".data(using: .ascii)!)
    le32(16); le16(1); le16(1); le32(sampleRate)
    le32(sampleRate * 2); le16(2); le16(16)
    wav.append("data".data(using: .ascii)!)
    le32(dataSize)
    wav.append(Data(count: dataSize))
    do {
      try wav.write(to: URL(fileURLWithPath: p))
      silencePath = p
      return p
    } catch {
      NSLog("[iosbg] silence file: \(error.localizedDescription)")
      return nil
    }
  }

  private func startSilence() {
    if silencePlayer?.isPlaying == true { startWatchdog(); return }
    guard let p = ensureSilenceFile() else { bgLog("startSilence: нет файла тишины"); return }
    do {
      // После записи плагин мог оставить категорию playAndRecord и погасить сессию —
      // принудительно возвращаем playback и активируем.
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, options: [.mixWithOthers])
      try session.setActive(true)
      let player = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: p))
      player.numberOfLoops = -1
      player.volume = 0.0
      player.prepareToPlay()
      let started = player.play()
      silencePlayer = player
      bgLog("startSilence: play=\(started) isPlaying=\(player.isPlaying) cat=\(session.category.rawValue)")
      startWatchdog()
    } catch {
      bgLog("startSilence ОШИБКА: \(error.localizedDescription)")
    }
  }

  private func stopSilence() {
    watchdog?.invalidate()
    watchdog = nil
    silencePlayer?.stop()
    silencePlayer = nil
    endTask()
    bgLog("stopSilence: остановлено")
  }

  /// beginBackgroundTask как страховка (даёт ~30 с после сворачивания,
  /// пока поднимается аудиосеанс; не основной механизм).
  private func beginTask() {
    if bgTaskId != .invalid { return }
    bgTaskId = UIApplication.shared.beginBackgroundTask(withName: "dictapro_transcribe") { [weak self] in
      self?.endTask()
    }
    NSLog("[iosbg] background task began: \(bgTaskId.rawValue)")
  }

  private func endTask() {
    if bgTaskId == .invalid { return }
    UIApplication.shared.endBackgroundTask(bgTaskId)
    bgTaskId = .invalid
    NSLog("[iosbg] background task ended")
  }

  @objc private func onAudioInterruption(_ note: Notification) {
    guard
      let info = note.userInfo,
      let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
      typeValue == AVAudioSession.InterruptionType.ended.rawValue,
      let reasonValue = info[AVAudioSessionInterruptionOptionKey] as? UInt,
      reasonValue == AVAudioSession.InterruptionOptions.shouldResume.rawValue
    else { return }
    // Звонок закончился — поднимаем тишину обратно, иначе фон умрёт.
    if silencePlayer != nil {
      startSilence()
    }
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
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
