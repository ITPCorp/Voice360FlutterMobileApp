import AVFoundation
import CallKit
import CryptoKit
import Flutter
import PushKit
import UIKit
import UserNotifications
#if canImport(WebRTC)
import WebRTC
#endif

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, PKPushRegistryDelegate {
  private var pluginsRegistered = false
  private var voipRegistry: PKPushRegistry?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Show foreground notifications as banners + sound on iOS so a message
    // arriving while the app is open still surfaces (matches Android UX).
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    }
    // Register for remote notifications so APNs can hand FCM a token.
    // Permission is requested by the Dart side (PushService.onLoginSuccess).
    application.registerForRemoteNotifications()

    // App-wake: PushKit must be set up on every launch, including the
    // background launch a VoIP push itself causes.
    let registry = PKPushRegistry(queue: DispatchQueue.main)
    registry.delegate = self
    registry.desiredPushTypes = [.voIP]
    voipRegistry = registry
    _ = AppWakeCalls.shared  // creates the CXProvider

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // Normal launch: the storyboard's FlutterViewController creates the engine
  // when the window scene connects (iOS 27 SDK / UIScene, see
  // itp-tools/ios-build-mac/README.md).
  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    registerPlugins(with: engineBridge.pluginRegistry)
  }

  private func registerPlugins(with registry: FlutterPluginRegistry) {
    guard !pluginsRegistered else { return }
    pluginsRegistered = true
    GeneratedPluginRegistrant.register(with: registry)
    if let registrar = registry.registrar(forPlugin: "Voice360AppWake") {
      AppWakeCalls.shared.attach(messenger: registrar.messenger())
      let inbox = FlutterMethodChannel(name: "voice360/notification_inbox", binaryMessenger: registrar.messenger())
      inbox.setMethodCallHandler { call, result in
        let center = UNUserNotificationCenter.current()
        switch call.method {
        case "active":
          center.getDeliveredNotifications { notes in
            let rows: [[String: Any]] = notes.map { note in
              let info = note.request.content.userInfo
              return ["key": note.request.identifier, "payload": info["payload"] ?? info]
            }
            DispatchQueue.main.async { result(rows) }
          }
        case "remove":
          center.removeDeliveredNotifications(withIdentifiers: call.arguments as? [String] ?? [])
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
  }

  /// A VoIP push can launch the app in the background, where no window scene
  /// connects, so there is no FlutterViewController and no engine. Asking
  /// FlutterAppDelegate (a FlutterPluginRegistry) for a registrar creates and
  /// runs its launch engine; the storyboard's FlutterViewController takes that
  /// same engine if the UI comes up later, and didInitializeImplicitFlutterEngine
  /// then finds the plugins already registered. Returns true on a cold start.
  @discardableResult
  func ensureFlutterEngine() -> Bool {
    if pluginsRegistered { return false }
    registerPlugins(with: self)
    return true
  }

  // MARK: PushKit

  func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials,
                    for type: PKPushType) {
    guard type == .voIP else { return }
    let token = pushCredentials.token.map { String(format: "%02x", $0) }.joined()
    AppWakeCalls.shared.setVoipToken(token)
  }

  func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
    guard type == .voIP else { return }
    AppWakeCalls.shared.setVoipToken("")
  }

  func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload,
                    for type: PKPushType, completion: @escaping () -> Void) {
    let receivedAt = Int64(Date().timeIntervalSince1970 * 1000)
    guard type == .voIP else {
      completion()
      return
    }
    var data: [String: String] = [:]
    for (k, v) in payload.dictionaryPayload {
      guard let key = k as? String, key != "aps" else { continue }
      data[key] = "\(v)"
    }
    // iOS 13+: every VoIP push MUST be reported to CallKit before completion,
    // cancels included, or iOS kills the app and later stops delivering.
    AppWakeCalls.shared.handlePush(data, receivedAtMs: receivedAt,
                                   ensureEngine: { [weak self] in self?.ensureFlutterEngine() ?? false },
                                   completion: completion)
  }
}

/// CallKit + the `voice360/app_wake` channel to Dart (CallWakeService).
final class AppWakeCalls: NSObject, CXProviderDelegate {
  static let shared = AppWakeCalls()

  private enum State: String { case ringing, answered, ended }
  private struct Entry {
    let uuid: UUID
    var state: State
  }

  private let provider: CXProvider
  private var channel: FlutterMethodChannel?
  private var backgroundTasks = Set<UIBackgroundTaskIdentifier>()
  private var dartReady = false
  private var queue: [[String: Any]] = []
  private var calls: [String: Entry] = [:]  // call_id -> entry
  private var voipToken: String? = UserDefaults.standard.string(forKey: "voice360_voip_token")
  private static let endedKey = "voice360_app_wake_ended"

  private override init() {
    let config: CXProviderConfiguration
    if #available(iOS 14.0, *) {
      config = CXProviderConfiguration()
    } else {
      config = CXProviderConfiguration(localizedName: "VOICE360")
    }
    config.iconTemplateImageData = UIImage(named: "CallKitIcon")?.pngData()
    config.supportsVideo = false
    config.maximumCallGroups = 1
    config.maximumCallsPerCallGroup = 1
    config.supportedHandleTypes = [.phoneNumber, .generic]
    config.includesCallsInRecents = true
    provider = CXProvider(configuration: config)
    super.init()
    provider.setDelegate(self, queue: nil)
    // Route changes from anywhere (CallKit's own speaker button, a headset
    // plugged in or connected) update the in-call screen's Speaker button.
    NotificationCenter.default.addObserver(
      forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
    ) { [weak self] notification in
      self?.routeChanged(notification)
    }
    NotificationCenter.default.addObserver(
      forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
    ) { [weak self] _ in
      guard let self = self, self.dartReady else { return }
      // Take the grant synchronously, before UIKit can suspend the Flutter engine.
      let task = self.beginBackground()
      self.send(["event": "background", "id": task.rawValue])
    }
  }

  static func uuidFor(_ callId: String) -> UUID {
    // Same as Java UUID.nameUUIDFromBytes (Android side): MD5, version 3.
    var b = Array(Insecure.MD5.hash(data: Data("voice360:\(callId)".utf8)))
    b[6] = (b[6] & 0x0f) | 0x30
    b[8] = (b[8] & 0x3f) | 0x80
    return UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
                       b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
  }

  // MARK: Dart bridge

  func attach(messenger: FlutterBinaryMessenger) {
    let ch = FlutterMethodChannel(name: "voice360/app_wake", binaryMessenger: messenger)
    channel = ch
    dartReady = false
    ch.setMethodCallHandler { [weak self] call, result in
      self?.onMethod(call, result: result)
    }
  }

  private func onMethod(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    let callId = args["call_id"] as? String ?? ""
    switch call.method {
    case "ready":
      dartReady = true
      let events = queue
      queue.removeAll()
      result(["events": events, "voipToken": voipToken ?? ""])
    case "getVoipToken":
      result(voipToken)
    case "endCall":
      endCall(callId, reason: args["reason"] as? String ?? "ended")
      result(nil)
    case "markEnded":
      markEnded(callId)
      result(nil)
    case "audioRoute":
      result(audioRouteState())
    case "setAudioRoute":
      do {
        try setAudioRoute(args["route"] as? String ?? "")
        result(audioRouteState())
      } catch {
        result(FlutterError(code: "audio_route", message: error.localizedDescription, details: nil))
      }
    case "routeTrace":
      result(routeTrace)
    case "audioCallStarted":
      startAudioCall()
      result(nil)
    case "callEnded":
      finishAudioCall()
      result(nil)
    case "connected", "callOngoing":
      // callOngoing/callEnded drive Android's ongoing-call notification. On
      // iOS, CallKit (woken calls) and the green status-bar pill (any call
      // using the mic) bring the app back; Dart then opens the in-call screen.
      result(nil)
    case "beginBackground":
      result(beginBackground().rawValue)
    case "endBackground":
      if let raw = args["id"] as? Int {
        endBackground(UIBackgroundTaskIdentifier(rawValue: raw))
      }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func beginBackground() -> UIBackgroundTaskIdentifier {
    var id = UIBackgroundTaskIdentifier.invalid
    id = UIApplication.shared.beginBackgroundTask(withName: "sip-unregister") { [weak self] in
      self?.endBackground(id)
    }
    if id != .invalid { backgroundTasks.insert(id) }
    return id
  }

  private func endBackground(_ id: UIBackgroundTaskIdentifier) {
    if backgroundTasks.remove(id) != nil { UIApplication.shared.endBackgroundTask(id) }
  }

  private func publishAudioRoute() {
    guard dartReady else { return }
    var event = audioRouteState()
    event["event"] = "audioRoute"
    send(event)
  }

  private func send(_ event: [String: Any]) {
    if dartReady, let ch = channel {
      ch.invokeMethod("onEvent", arguments: event)
    } else {
      queue.append(event)
      if queue.count > 20 { queue.removeFirst() }
    }
  }

  func setVoipToken(_ token: String) {
    voipToken = token.isEmpty ? nil : token
    UserDefaults.standard.set(voipToken, forKey: "voice360_voip_token")
    if !token.isEmpty { send(["event": "voipToken", "token": token]) }
  }

  // MARK: Audio route (in-call screen Speaker button)

  private static func routeName(_ port: AVAudioSession.Port) -> String {
    switch port {
    case .builtInSpeaker: return "speaker"
    case .builtInReceiver: return "earpiece"
    case .bluetoothHFP, .bluetoothA2DP, .bluetoothLE, .carAudio: return "bluetooth"
    case .headphones, .headsetMic, .usbAudio, .lineOut: return "wired"
    default: return "external"
    }
  }

  private var audioCallActive = false

  private func startAudioCall() {
    guard !audioCallActive else { return } // CallKit Answer can precede the SIP INVITE.
    audioCallActive = true
    intentRevision += 1
  }

  private func finishAudioCall() {
    audioCallActive = false
    intentRevision += 1
    speakerIntent.followDevice()
    repairTime = nil
    expectedOverrides.removeAll()
  }

  private var routeSequence = 0
  private var intentRevision = 0
  private var speakerIntent = SpeakerIntent()
  private var applyingOverride = false
  private var repairTime: TimeInterval?
  private var expectedOverrides: [(previous: String?, until: TimeInterval)] = []
  private var routeTrace: [[String: Any]] = []
  private var traceSequence = 0
  private let traceClock: ISO8601DateFormatter = {
    let clock = ISO8601DateFormatter()
    clock.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return clock
  }()

  private func outputName(_ route: AVAudioSessionRouteDescription?) -> String? {
    let ports = route?.outputs.map { Self.routeName($0.portType) } ?? []
    return ports.contains("speaker") ? "speaker" : ports.first
  }

  private func audioRouteState() -> [String: Any] {
    let session = AVAudioSession.sharedInstance()
    var available = ["earpiece", "speaker"]
    var btName: String?
    for input in session.availableInputs ?? [] {
      let name = Self.routeName(input.portType)
      if name == "bluetooth" { btName = input.portName }
      if (name == "bluetooth" || name == "wired") && !available.contains(name) { available.append(name) }
    }
    routeSequence += 1
    var state: [String: Any] = ["sequence": routeSequence, "available": available, "via": "avaudiosession"]
    state["bluetooth_name"] = btName
    state["route"] = speakerIntent.displayRoute(outputName(session.currentRoute))
    return state
  }

  // One row per tap/notification. Fill in the settled ports on the same row
  // without changing event order, even when several notifications overlap.
  private func trace(_ reason: String, previous: String? = nil) -> Int {
    traceSequence += 1
    var row: [String: Any] = ["sequence": traceSequence, "time": traceClock.string(from: Date()),
                              "reason": reason, "override": "unchanged"]
    row["previous"] = previous
    routeTrace.append(row)
    if routeTrace.count > 30 { routeTrace.removeFirst() }
    return traceSequence
  }

  private func sample(_ id: Int) {
    guard let i = routeTrace.firstIndex(where: { $0["sequence"] as? Int == id }) else { return }
    let s = AVAudioSession.sharedInstance()
    routeTrace[i]["category"] = s.category.rawValue
    routeTrace[i]["mode"] = s.mode.rawValue
    routeTrace[i]["outputs"] = s.currentRoute.outputs.map {
      ["portType": $0.portType.rawValue, "portName": $0.portName]
    }
    routeTrace[i]["speakerWanted"] = speakerIntent.speakerWanted
  }

  private func applyOverride(_ on: Bool, event: Int) throws {
    let session = AVAudioSession.sharedInstance()
    let now = ProcessInfo.processInfo.systemUptime
    expectedOverrides.removeAll { $0.until < now }
    expectedOverrides.append((outputName(session.currentRoute), now + 1))
    applyingOverride = true
    defer { applyingOverride = false }
    if let i = routeTrace.firstIndex(where: { $0["sequence"] as? Int == event }) { routeTrace[i]["override"] = on ? "speaker" : "none" }
    do {
      try session.overrideOutputAudioPort(on ? .speaker : .none)
    } catch {
      expectedOverrides.removeAll()
      if let i = routeTrace.firstIndex(where: { $0["sequence"] as? Int == event }) {
        routeTrace[i]["error"] = error.localizedDescription
      }
      throw error
    }
  }

  private func setAudioRoute(_ requested: String) throws {
    let on = requested == "toggleSpeaker" ? !speakerIntent.speakerWanted : requested == "speaker"
    let id = trace("app." + requested)
    intentRevision += 1
    repairTime = nil
    let before = speakerIntent
    speakerIntent.select(on)
    defer { publishAfterSettling(id) }
    do {
      try applyOverride(on, event: id)
    } catch {
      speakerIntent = before
      throw error
    }
    if !on {
      let session = AVAudioSession.sharedInstance()
      let input = session.availableInputs?.first {
        requested == "earpiece" ? $0.portType == .builtInMic : Self.routeName($0.portType) == requested
      }
      try session.setPreferredInput(input)
    }
  }

  private func publishAfterSettling(_ id: Int) {
    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(250)) {
      self.sample(id)
      self.publishAudioRoute()
    }
  }

  private func routeChanged(_ notification: Notification) {
    let info = notification.userInfo
    let raw = info?[AVAudioSessionRouteChangeReasonKey] as? UInt ?? 0
    let reason: String
    switch AVAudioSession.RouteChangeReason(rawValue: raw) {
    case .categoryChange: reason = "categoryChange"
    case .override: reason = "override"
    case .routeConfigurationChange: reason = "routeConfigurationChange"
    case .newDeviceAvailable: reason = "newDeviceAvailable"
    case .oldDeviceUnavailable: reason = "oldDeviceUnavailable"
    case .wakeFromSleep: reason = "wakeFromSleep"
    case .noSuitableRouteForCategory: reason = "noSuitableRouteForCategory"
    default: reason = "unknown(" + String(raw) + ")"
    }
    let previous = outputName(info?[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription)
    var own = applyingOverride
    let now = ProcessInfo.processInfo.systemUptime
    if (reason == "categoryChange" || reason == "routeConfigurationChange"),
       let repairTime = repairTime, now - repairTime < 0.25 {
      own = true // A repair can itself reconfigure the session.
    }
    if reason == "override" {
      expectedOverrides.removeAll { $0.until < now }
      if let i = expectedOverrides.firstIndex(where: { $0.previous == previous }) {
        expectedOverrides.remove(at: i)
        own = true
      }
      if !own && UIApplication.shared.applicationState != .active { intentRevision += 1 }
    }
    if reason == "newDeviceAvailable" || reason == "oldDeviceUnavailable" {
      intentRevision += 1
      speakerIntent.followDevice()
      expectedOverrides.removeAll()
    }
    settle(reason, previous: previous, own: own)
  }

  private func settle(_ reason: String, previous: String? = nil, own: Bool = false) {
    let id = trace(reason, previous: previous)
    let revision = intentRevision
    let systemControls = UIApplication.shared.applicationState != .active
    routeTrace[routeTrace.count - 1]["systemControls"] = systemControls
    routeTrace[routeTrace.count - 1]["ownOverride"] = own
    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(250)) {
      if self.audioCallActive && revision == self.intentRevision {
        let output = self.outputName(AVAudioSession.sharedInstance().currentRoute)
        if self.speakerIntent.settle(reason: reason, previous: previous, output: output,
                                     ownOverride: own, systemControls: systemControls) {
          if let i = self.routeTrace.firstIndex(where: { $0["sequence"] as? Int == id }) {
            self.routeTrace[i]["outputsBeforeRepair"] = AVAudioSession.sharedInstance().currentRoute.outputs.map {
              ["portType": $0.portType.rawValue, "portName": $0.portName]
            }
          }
          self.repairTime = ProcessInfo.processInfo.systemUptime
          try? self.applyOverride(true, event: id)
          self.publishAfterSettling(id)
          return
        }
      }
      self.sample(id)
      self.publishAudioRoute()
    }
  }

  // MARK: Pushes

  func handlePush(_ data: [String: String], receivedAtMs: Int64,
                  ensureEngine: () -> Bool, completion: @escaping () -> Void) {
    let action = data["action"] ?? ""
    let callId = data["call_id"] ?? ""
    guard data["type"] == "voice360_call", !callId.isEmpty, action == "ring" || action == "cancel" else {
      NSLog("[AppWake] unexpected VoIP push \(data)")
      reportAndEnd(completion)
      return
    }
    var event: [String: Any] = data
    event["event"] = "push"
    event["received_at_ms"] = String(receivedAtMs)

    if action == "ring" {
      if let e = calls[callId], e.state != .ended {
        NSLog("[AppWake] duplicate ring \(callId)")
        reportExisting(e.uuid, completion)
        return
      }
      if isEnded(callId) {
        NSLog("[AppWake] ring for ended call \(callId)")
        reportAndEnd(completion)
        return
      }
      let cold = ensureEngine()
      let uuid = AppWakeCalls.uuidFor(callId)
      event["uuid"] = uuid.uuidString
      event["cold_start"] = cold ? "1" : "0"
      let number = data["caller_id_number"] ?? ""
      let name = data["caller_id_name"] ?? ""
      let update = CXCallUpdate()
      update.remoteHandle = CXHandle(type: number.isEmpty ? .generic : .phoneNumber,
                                     value: number.isEmpty ? "Caller ID unavailable" : number)
      update.localizedCallerName = name.isEmpty ? nil : name
      update.hasVideo = false
      update.supportsDTMF = true
      update.supportsHolding = false
      update.supportsGrouping = false
      update.supportsUngrouping = false
      calls[callId] = Entry(uuid: uuid, state: .ringing)
      provider.reportNewIncomingCall(with: uuid, update: update) { [weak self] error in
        guard let self = self else { completion(); return }
        if let error = error {
          // Do Not Disturb, blocked number, a call already up, ...
          NSLog("[AppWake] reportNewIncomingCall failed: \(error)")
          self.calls[callId]?.state = .ended
          self.markEnded(callId)
          event["native_result"] = "report_failed"
          self.send(event)
          self.send(["event": "end", "uuid": uuid.uuidString])
        } else {
          event["native_result"] = "shown"
          self.send(event)
        }
        completion()
      }
      return
    }

    // cancel
    guard let e = calls[callId], e.state == .ringing else {
      // F4: already answered/declined/ended here, or never shown in this
      // process. Report + end a throwaway call to satisfy PushKit.
      NSLog("[AppWake] cancel for \(callId) ignored (\(calls[callId]?.state.rawValue ?? "unknown"))")
      if let e = calls[callId], e.state == .answered {
        reportExisting(e.uuid, completion)  // no second call UI over the live one
      } else {
        reportAndEnd(completion)
      }
      if dartReady {
        event["uuid"] = AppWakeCalls.uuidFor(callId).uuidString
        event["native_result"] = "ignored"
        send(event)
      }
      return
    }
    provider.reportCall(with: e.uuid, endedAt: Date(), reason: endedReason(data["reason"] ?? "missed"))
    calls[callId]?.state = .ended
    markEnded(callId)
    event["uuid"] = e.uuid.uuidString
    event["native_result"] = "ended"
    send(event)
    completion()
  }

  /// Report a throwaway call and end it at once (the PushKit rule for pushes
  /// that must not ring).
  private func reportAndEnd(_ completion: @escaping () -> Void) {
    let uuid = UUID()
    let update = CXCallUpdate()
    update.remoteHandle = CXHandle(type: .generic, value: "VOICE360")
    update.hasVideo = false
    provider.reportNewIncomingCall(with: uuid, update: update) { [weak self] _ in
      self?.provider.reportCall(with: uuid, endedAt: Date(), reason: .remoteEnded)
      completion()
    }
  }

  /// Re-report a call CallKit already has: it answers "already exists" and
  /// shows nothing, which still counts as reporting the push.
  private func reportExisting(_ uuid: UUID, _ completion: @escaping () -> Void) {
    let update = CXCallUpdate()
    update.remoteHandle = CXHandle(type: .generic, value: "VOICE360")
    provider.reportNewIncomingCall(with: uuid, update: update) { _ in completion() }
  }

  private func endedReason(_ r: String) -> CXCallEndedReason {
    switch r {
    case "answered_elsewhere": return .answeredElsewhere
    case "declined", "declined_elsewhere": return .declinedElsewhere
    case "failed": return .failed
    case "ended", "caller_hangup": return .remoteEnded
    default: return .unanswered  // missed
    }
  }

  private func endCall(_ callId: String, reason: String) {
    guard let e = calls[callId] else { markEnded(callId); return }
    if e.state == .answered { finishAudioCall() }
    if e.state != .ended {
      provider.reportCall(with: e.uuid, endedAt: Date(), reason: endedReason(reason))
    }
    calls[callId]?.state = .ended
    markEnded(callId)
  }

  private func callId(for uuid: UUID) -> String? {
    calls.first(where: { $0.value.uuid == uuid })?.key
  }

  private func isEnded(_ callId: String) -> Bool {
    (UserDefaults.standard.stringArray(forKey: AppWakeCalls.endedKey) ?? []).contains(callId)
  }

  private func markEnded(_ callId: String) {
    guard !callId.isEmpty else { return }
    var list = (UserDefaults.standard.stringArray(forKey: AppWakeCalls.endedKey) ?? []).filter { $0 != callId }
    list.append(callId)
    if list.count > 30 { list.removeFirst(list.count - 30) }
    UserDefaults.standard.set(list, forKey: AppWakeCalls.endedKey)
    // Drop finished entries so the map does not grow.
    if calls[callId]?.state == .ended { calls.removeValue(forKey: callId) }
  }

  // MARK: CXProviderDelegate

  func providerDidReset(_ provider: CXProvider) {
    finishAudioCall()
    NSLog("[AppWake] provider reset")
    for (id, e) in calls where e.state != .ended {
      send(["event": "end", "uuid": e.uuid.uuidString])
      markEnded(id)
    }
    calls.removeAll()
  }

  func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
    guard let id = callId(for: action.callUUID) else {
      action.fail()
      return
    }
    startAudioCall()
    calls[id]?.state = .answered
    let session = AVAudioSession.sharedInstance()
    try? session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth])
    send(["event": "answer", "uuid": action.callUUID.uuidString])
    action.fulfill()
  }

  func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
    if let id = callId(for: action.callUUID) {
      if calls[id]?.state == .answered { finishAudioCall() }
      calls[id]?.state = .ended
      markEnded(id)
    }
    send(["event": "end", "uuid": action.callUUID.uuidString])
    action.fulfill()
  }

  func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
    send(["event": "mute", "uuid": action.callUUID.uuidString, "muted": action.isMuted ? "1" : "0"])
    action.fulfill()
  }

  func provider(_ provider: CXProvider, perform action: CXSetHeldCallAction) {
    action.fail()
  }

  func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
    #if canImport(WebRTC)
    RTCAudioSession.sharedInstance().audioSessionDidActivate(audioSession)
    #endif
    settle("didActivate")
    send(["event": "audio", "active": "1"])
  }

  func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
    #if canImport(WebRTC)
    RTCAudioSession.sharedInstance().audioSessionDidDeactivate(audioSession)
    #endif
    send(["event": "audio", "active": "0"])
  }
}
