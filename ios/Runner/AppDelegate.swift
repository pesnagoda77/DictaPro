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
        case "openFolder":
          // На iOS «папку» показывает свой экран со списком файлов
          // (Dart: RecordingsFolderPage). Здесь — просто успех.
          result(true)
        case "extractFragmentWav":
          // Славан: «не удалось вырезать фрагмент» на iPhone — обработчика
          // не было вовсе (он был только в Android MainActivity).
          let args = call.arguments as? [String: Any]
          guard let path = args?["path"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "path is null", details: nil))
            return
          }
          let fromMs = (args?["fromMs"] as? Int) ?? 0
          let toMs = (args?["toMs"] as? Int) ?? 0
          DispatchQueue.global(qos: .userInitiated).async {
            do {
              let out = try FragmentExtractor.extract(path: path, fromMs: fromMs, toMs: toMs)
              DispatchQueue.main.async { result(out) }
            } catch {
              DispatchQueue.main.async {
                result(FlutterError(code: "EXTRACT_FAILED",
                                    message: error.localizedDescription,
                                    details: nil))
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

/// Пишет 16 кГц моно 16-bit PCM WAV. Наши записи — WAV PCM, читаются
/// напрямую RIFF-парсингом (task 099: AVAudioFile.read падает
/// _GenericObjCError на JUNK/FLLR-чанках iOS-рекордера). Прочие форматы —
/// fallback через AVAudioFile. Ресемплинг линейный, без AVAudioConverter.
enum Wav16kConverter {
  static let targetRate: Double = 16000
  static var lastStage = "init"

  /// Описание data-чанка PCM-WAV.
  struct WavInfo {
    var dataOffset: UInt64
    var dataSize: UInt64
    var sampleRate: Double
    var channels: Int
  }

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

  // MARK: - little-endian helpers

  static func u16le(_ d: Data, _ i: Int) -> UInt16 {
    UInt16(d[i]) | (UInt16(d[i + 1]) << 8)
  }
  static func u32le(_ d: Data, _ i: Int) -> UInt32 {
    UInt32(d[i]) | (UInt32(d[i + 1]) << 8) | (UInt32(d[i + 2]) << 16) | (UInt32(d[i + 3]) << 24)
  }
  static func isTag(_ d: Data, _ i: Int, _ s: String) -> Bool {
    let b = Array(s.utf8)
    return d[i] == b[0] && d[i + 1] == b[1] && d[i + 2] == b[2] && d[i + 3] == b[3]
  }

  // MARK: - entry point

  static func convert(inputPath: String, outputPath: String) throws {
    lastStage = "open_source"
    log("start input=\(inputPath) output=\(outputPath)")
    let srcUrl = URL(fileURLWithPath: inputPath)
    let fm = FileManager.default
    try? fm.removeItem(atPath: outputPath)
    fm.createFile(atPath: outputPath, contents: nil)
    guard let out = FileHandle(forWritingAtPath: outputPath) else {
      throw NSError(domain: "dictapro", code: 11, userInfo: [NSLocalizedDescriptionKey: "cannot open output file"])
    }
    out.write(Data(count: 44))

    lastStage = "prepare"
    let dataBytes: UInt32
    if let info = try? parseWavPcm(srcUrl) {
      log("path=pcm-direct rate=\(info.sampleRate) ch=\(info.channels) dataBytes=\(info.dataSize)")
      dataBytes = try convertPcmDirect(info, url: srcUrl, out: out)
    } else {
      log("path=avaudiofile fallback (не WAV PCM — читаем через AVAudioFile)")
      dataBytes = try convertViaAVAudioFile(url: srcUrl, out: out)
    }

    lastStage = "write_header"
    log("pcm bytes=\(dataBytes)")
    writeHeader(out: out, dataBytes: dataBytes)

    lastStage = "done"
    log("finished output=\(outputPath)")
    out.closeFile()
  }

  // MARK: - RIFF parsing (task 099)

  /// Парсит RIFF/WAVE, находит fmt и data чанки. Принимает только PCM 16-bit.
  /// Терпит нефинализированный заголовок (data size=0, task 099): берёт
  /// данные до конца файла.
  static func parseWavPcm(_ url: URL) throws -> WavInfo {
    let h = try FileHandle(forReadingFrom: url)
    defer { h.closeFile() }
    func rdExact(_ n: Int) throws -> Data {
      guard let d = try h.read(upToCount: n), d.count == n else {
        throw NSError(domain: "dictapro", code: 20, userInfo: [NSLocalizedDescriptionKey: "unexpected eof"])
      }
      return d
    }
    let riff = try rdExact(12)
    guard isTag(riff, 0, "RIFF"), isTag(riff, 8, "WAVE") else {
      throw NSError(domain: "dictapro", code: 21, userInfo: [NSLocalizedDescriptionKey: "not a RIFF/WAVE file"])
    }
    var rate: Double = 0
    var ch = 0
    var bits = 0
    var format = 0
    var fmtOk = false
    var dataOff: UInt64?
    var dataSize: UInt64?
    while true {
      guard let head = try h.read(upToCount: 8), head.count == 8 else { break }
      let sz = u32le(head, 4)
      let bodyOff = h.offsetInFile
      if isTag(head, 0, "fmt ") {
        let f = try rdExact(Int(sz))
        guard f.count >= 16 else {
          throw NSError(domain: "dictapro", code: 22, userInfo: [NSLocalizedDescriptionKey: "short fmt chunk"])
        }
        format = Int(u16le(f, 0))
        ch = Int(u16le(f, 2))
        rate = Double(u32le(f, 4))
        bits = Int(u16le(f, 14))
        fmtOk = true
      } else if isTag(head, 0, "data") {
        dataOff = bodyOff
        dataSize = UInt64(sz)
        break // дальше чанков не нужно
      }
      var next = bodyOff + UInt64(sz)
      if sz & 1 == 1 { next += 1 } // pad до чётного
      h.seek(toFileOffset: next)
    }
    guard fmtOk, let dOff = dataOff, var dSize = dataSize else {
      throw NSError(domain: "dictapro", code: 23, userInfo: [NSLocalizedDescriptionKey: "no fmt/data chunk"])
    }
    guard format == 1, bits == 16, ch > 0, rate > 0 else {
      throw NSError(domain: "dictapro", code: 24, userInfo: [NSLocalizedDescriptionKey: "not 16-bit PCM (\(format)/\(bits)bit/\(ch)ch)"])
    }
    // Нефинализированный заголовок (остановка записи, task 099):
    // размер data=0 или за пределами файла → берём до конца файла.
    let fileEnd = h.seekToEndOfFile()
    if dSize == 0 || dOff &+ dSize > fileEnd {
      dSize = fileEnd - dOff
    }
    return WavInfo(dataOffset: dOff, dataSize: dSize, sampleRate: rate, channels: ch)
  }

  // MARK: - PCM-direct path (task 099)

  /// Читает data-чанк сырыми байтами (Int16 LE → Float), ресемплит в 16 кГц.
  static func convertPcmDirect(_ info: WavInfo, url: URL, out: FileHandle) throws -> UInt32 {
    let h = try FileHandle(forReadingFrom: url)
    defer { h.closeFile() }
    h.seek(toFileOffset: info.dataOffset)
    let step = info.sampleRate / targetRate
    let srcCh = info.channels
    let bytesPerFrame = UInt64(srcCh * 2)
    let chunkFrames: UInt64 = 16384
    var pos: Double = 0
    var base: Double = 0
    var pending = Data()
    var dataBytes: UInt32 = 0
    var readBytes: UInt64 = 0
    var lastFrame: [Float]? = nil

    while readBytes < info.dataSize {
      let want = min(chunkFrames * bytesPerFrame, info.dataSize - readBytes)
      guard want > 0, let raw = try h.read(upToCount: Int(want)), !raw.isEmpty else { break }
      readBytes += UInt64(raw.count)
      let n = raw.count / Int(bytesPerFrame)
      if n == 0 { break }
      var chans = [[Float]](repeating: [Float](repeating: 0, count: n), count: srcCh)
      raw.withUnsafeBytes { ptr in
        guard let p = ptr.baseAddress?.assumingMemoryBound(to: Int16.self) else { return }
        for f in 0..<n {
          for c in 0..<srcCh {
            chans[c][f] = Float(p[f * srcCh + c]) * (1.0 / 32768.0)
          }
        }
      }
      consumeChans(chans, n, srcCh: srcCh, step: step, pos: &pos, base: &base, pending: &pending,
                   lastFrame: &lastFrame)
      flush(&pending, to: out, dataBytes: &dataBytes)
    }
    flushTail(&pending, to: out, dataBytes: &dataBytes)
    return dataBytes
  }

  // MARK: - AVAudioFile fallback

  /// Старый путь для не-WAV/не-PCM источников (m4a и т.п.).
  static func convertViaAVAudioFile(url: URL, out: FileHandle) throws -> UInt32 {
    let src = try AVAudioFile(forReading: url)
    let fmt = src.processingFormat
    let srcRate = fmt.sampleRate
    let srcCh = Int(fmt.channelCount)
    guard srcRate > 0, srcCh > 0 else {
      throw NSError(domain: "dictapro", code: 10, userInfo: [NSLocalizedDescriptionKey: "unreadable source format"])
    }
    log("fallback source rate=\(srcRate) ch=\(srcCh)")
    let step = srcRate / targetRate
    let chunkFrames: AVAudioFrameCount = 32768
    var pos: Double = 0
    var base: Double = 0
    var pending = Data()
    var dataBytes: UInt32 = 0
    var lastFrame: [Float]? = nil

    while true {
      guard let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: chunkFrames) else { break }
      try src.read(into: buf)
      let n = Int(buf.frameLength)
      if n == 0 { break }
      guard let chData = buf.floatChannelData else { break }
      consumeUnsafe(chData, n, srcCh: srcCh, step: step, pos: &pos, base: &base, pending: &pending,
                    lastFrame: &lastFrame)
      flush(&pending, to: out, dataBytes: &dataBytes)
    }
    flushTail(&pending, to: out, dataBytes: &dataBytes)
    return dataBytes
  }

  // MARK: - resampling

  /// Линейный ресемплинг блока кадров в 16 кГц моно; дописывает Int16 LE.
  static func consumeChans(_ chData: [[Float]], _ n: Int, srcCh: Int, step: Double,
                           pos: inout Double, base: inout Double, pending: inout Data,
                           lastFrame: inout [Float]?) {
    var i0 = Int(floor(pos - base))
    while Double(i0) + 1.0 < Double(n) {
      let t = Float(pos - base - Double(i0))
      var acc: Float = 0
      for c in 0..<srcCh {
        let s = chData[c]
        if i0 < 0 {
          // Стык блоков: левый кадр — последний кадр предыдущего блока
          // (task 100: без этого i0 == -1 читал бы память вне буфера;
          //  для Swift Array это выход за границы и краш).
          let left = (lastFrame?.count == srcCh) ? lastFrame![c] : s[0]
          acc += left * (1 - t) + s[0] * t
        } else {
          acc += s[i0] * (1 - t) + s[i0 + 1] * t
        }
      }
      acc /= Float(srcCh)
      appendSample(acc, to: &pending)
      pos += step
      i0 = Int(floor(pos - base))
    }
    var lf = [Float](repeating: 0, count: srcCh)
    for c in 0..<srcCh { lf[c] = chData[c][n - 1] }
    lastFrame = lf
    base += Double(n)
  }

  static func consumeUnsafe(_ chData: UnsafePointer<UnsafeMutablePointer<Float>>, _ n: Int, srcCh: Int,
                            step: Double, pos: inout Double, base: inout Double, pending: inout Data,
                            lastFrame: inout [Float]?) {
    var i0 = Int(floor(pos - base))
    while Double(i0) + 1.0 < Double(n) {
      let t = Float(pos - base - Double(i0))
      var acc: Float = 0
      for c in 0..<srcCh {
        let s = chData[c]
        if i0 < 0 {
          // Стык блоков: левый кадр — последний кадр предыдущего блока.
          let left = (lastFrame?.count == srcCh) ? lastFrame![c] : s[0]
          acc += left * (1 - t) + s[0] * t
        } else {
          acc += s[i0] * (1 - t) + s[i0 + 1] * t
        }
      }
      acc /= Float(srcCh)
      appendSample(acc, to: &pending)
      pos += step
      i0 = Int(floor(pos - base))
    }
    var lf = [Float](repeating: 0, count: srcCh)
    for c in 0..<srcCh { lf[c] = chData[c][n - 1] }
    lastFrame = lf
    base += Double(n)
  }

  static func appendSample(_ acc: Float, to pending: inout Data) {
    let clipped = max(-1.0, min(1.0, acc))
    var v = Int16(clipped * 32767.0).littleEndian
    withUnsafeBytes(of: &v) { pending.append(contentsOf: $0) }
  }

  static func flush(_ pending: inout Data, to out: FileHandle, dataBytes: inout UInt32) {
    if pending.count >= 1 << 20 {
      out.write(pending)
      dataBytes &+= UInt32(pending.count)
      pending.removeAll(keepingCapacity: true)
    }
  }

  static func flushTail(_ pending: inout Data, to out: FileHandle, dataBytes: inout UInt32) {
    if !pending.isEmpty {
      out.write(pending)
      dataBytes &+= UInt32(pending.count)
    }
  }

  // MARK: - RIFF header

  static func writeHeader(out: FileHandle, dataBytes: UInt32) {
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
    out.seek(toFileOffset: 0)
    out.write(header)
  }
}


/// Вырезание фрагмента на iOS: AVAssetReader декодирует диапазон в PCM,
/// пишем обычный WAV (16 кГц моно, 16 бит) — гарантированно играется везде.
enum FragmentExtractor {
  static func extract(path: String, fromMs: Int, toMs: Int) throws -> String {
    let url = URL(fileURLWithPath: path)
    let asset = AVURLAsset(url: url)
    guard let track = asset.tracks(withMediaType: .audio).first else {
      throw NSError(domain: "dictapro", code: 31,
                    userInfo: [NSLocalizedDescriptionKey: "в файле нет аудиодорожки"])
    }

    let reader = try AVAssetReader(asset: asset)
    let from = max(0, fromMs)
    var to = max(from + 300, toMs)
    let durMs = Int(CMTimeGetSeconds(asset.duration) * 1000)
    if durMs > 0 { to = min(to, durMs) }
    reader.timeRange = CMTimeRange(
      start: CMTime(value: CMTimeValue(from), timescale: 1000),
      duration: CMTime(value: CMTimeValue(max(0, to - from)), timescale: 1000))

    let settings: [String: Any] = [
      AVFormatIDKey: kAudioFormatLinearPCM,
      AVSampleRateKey: 16000.0,
      AVNumberOfChannelsKey: 1,
      AVLinearPCMBitDepthKey: 16,
      AVLinearPCMIsFloatKey: false,
      AVLinearPCMIsBigEndianKey: false,
      AVLinearPCMIsNonInterleaved: false,
    ]
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
    output.alwaysCopiesSampleData = false
    guard reader.canAdd(output) else {
      throw NSError(domain: "dictapro", code: 32,
                    userInfo: [NSLocalizedDescriptionKey: "не удалось настроить чтение"])
    }
    reader.add(output)
    guard reader.startReading() else {
      throw NSError(domain: "dictapro", code: 33,
                    userInfo: [NSLocalizedDescriptionKey: reader.error?.localizedDescription ?? "reader не стартовал"])
    }

    var pcm = Data()
    while let sample = output.copyNextSampleBuffer() {
      defer { CMSampleBufferInvalidate(sample) }
      guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
      var length = 0
      var pointer: UnsafeMutablePointer<Int8>?
      let status = CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil,
                                              totalLengthOut: &length, dataPointerOut: &pointer)
      if status == kCMBlockBufferNoErr, let p = pointer, length > 0 {
        pcm.append(UnsafeBufferPointer(start: UnsafeRawPointer(p).assumingMemoryBound(to: UInt8.self),
                                       count: length))
      }
    }
    if reader.status == .failed {
      throw NSError(domain: "dictapro", code: 34,
                    userInfo: [NSLocalizedDescriptionKey: reader.error?.localizedDescription ?? "чтение прервано"])
    }

    // WAV-заголовок (16 кГц, моно, 16 бит).
    var out = Data()
    func le32(_ v: UInt32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { out.append(contentsOf: $0) } }
    func le16(_ v: UInt16) { var x = v.littleEndian; withUnsafeBytes(of: &x) { out.append(contentsOf: $0) } }
    let rate: UInt32 = 16000
    let dataBytes = UInt32(pcm.count)
    out.append(contentsOf: Array("RIFF".utf8)); le32(36 &+ dataBytes)
    out.append(contentsOf: Array("WAVE".utf8))
    out.append(contentsOf: Array("fmt ".utf8)); le32(16)
    le16(1); le16(1); le32(rate); le32(rate &* 2); le16(2); le16(16)
    out.append(contentsOf: Array("data".utf8)); le32(dataBytes)
    out.append(pcm)

    let tmp = NSTemporaryDirectory() + "fragment_\(Int(Date().timeIntervalSince1970 * 1000)).wav"
    try out.write(to: URL(fileURLWithPath: tmp))
    return tmp
  }
}
