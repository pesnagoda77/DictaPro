import AVFoundation
import Flutter
import UIKit

/// Task 056: расшифровка на iOS не должна умирать при выключенном экране.
/// На Android фон держит foreground-служба; на iOS её нет — держим живой
/// аудиосеанс: режим UIBackgroundModes: audio (уже в Info.plist) +
/// воспроизведение тишины (стандартный приём: активный аудиопоток не даёт
/// системе усыпить процесс). beginBackgroundTask — только доп. страховка.
@main
@objc class AppDelegate: FlutterAppDelegate {
  private var silencePlayer: AVAudioPlayer?
  private var silencePath: String?
  private var bgTaskId: UIBackgroundTaskIdentifier = .invalid
  private var bgChannel: FlutterMethodChannel?

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

    // Канал регистрируем после super: к этому моменту storyboard-window
    // уже создан и rootViewController — FlutterViewController.
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
    if silencePlayer?.isPlaying == true { return }
    guard let p = ensureSilenceFile() else { return }
    do {
      let player = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: p))
      player.numberOfLoops = -1 // бесконечный цикл
      player.volume = 0.0        // тишина, не раздражает
      player.prepareToPlay()
      player.play()
      silencePlayer = player
      NSLog("[iosbg] silence started")
    } catch {
      NSLog("[iosbg] player: \(error.localizedDescription)")
    }
  }

  private func stopSilence() {
    silencePlayer?.stop()
    silencePlayer = nil
    NSLog("[iosbg] silence stopped")
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
