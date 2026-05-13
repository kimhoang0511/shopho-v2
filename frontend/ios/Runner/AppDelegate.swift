import AVFoundation
import CallKit
import Firebase
import Flutter
import PushKit
import UIKit
import UserNotifications
import flutter_callkit_incoming

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate,
                         PKPushRegistryDelegate, CXCallObserverDelegate,
                         CallkitIncomingAppDelegate {

  private static let kChannel          = "shopho/call_native"
  private static let kNotifChannel     = "shopho/notif_tap"
  private static let kPendingAccept    = "shopho_pending_accept_call_id"
  private static let kPendingTs        = "shopho_pending_accept_ts"
  private static let kVoipPrefix       = "shopho_voip_call_"
  private static let kPendingOrder     = "shopho_pending_order_tap"
  private static let kVoipToken        = "shopho_voip_push_token"
  // Full accept snapshot: written in onAccept before any Dart processing.
  // Key: kPendingCallFull + callId (lowercased).
  private static let kPendingCallFull  = "shopho_pending_call_full_"

  // CXCallObserver must be retained for the lifetime of the app.
  private let callObserver = CXCallObserver()

  // PKPushRegistry MUST be retained as a property — if stored as a local variable
  // inside application(_:didFinishLaunchingWithOptions:), ARC releases it immediately
  // after the method returns and didUpdate is never called, so no VoIP token is delivered.
  private var voipRegistry: PKPushRegistry?

  // Retained so AppDelegate.didReceive can invoke onTap for foreground taps.
  private var notifTapChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    FirebaseApp.configure()
    UNUserNotificationCenter.current().delegate = self
    application.registerForRemoteNotifications()

    // Register for VoIP push (PushKit) so flutter_callkit_incoming gets a VoIP token.
    // Stored as a property — a local variable would be released by ARC at method return.
    let registry = PKPushRegistry(queue: DispatchQueue.main)
    registry.delegate = self
    registry.desiredPushTypes = [.voIP]
    voipRegistry = registry

    // Watch CallKit call state changes to detect user-accepted calls natively.
    // This fires even when the Flutter engine is not yet ready.
    callObserver.setDelegate(self, queue: DispatchQueue.main)

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // MARK: - FlutterImplicitEngineDelegate

  // This fires when the Flutter engine is initialised — this is the ONLY reliable
  // place to set up MethodChannels when using a Scene-based lifecycle (iOS 13+),
  // because AppDelegate.window is nil (windows are owned by SceneDelegate).
  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AppDelegateChannels") else { return }
    setupChannels(messenger: registrar.messenger())
  }

  // MARK: - Channel Setup

  private func setupChannels(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: AppDelegate.kChannel,
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { call, result in
      let defaults = UserDefaults.standard
      switch call.method {

      // Mirror of Android's getPendingAcceptCallId — returns the callId saved
      // by CXCallObserverDelegate when the user accepted before the Dart
      // EventChannel listener was registered (cold-start race condition).
      case "getPendingAcceptCallId":
        let callId = defaults.string(forKey: AppDelegate.kPendingAccept)
        let ts     = defaults.double(forKey: AppDelegate.kPendingTs)
        defaults.removeObject(forKey: AppDelegate.kPendingAccept)
        defaults.removeObject(forKey: AppDelegate.kPendingTs)
        // Discard stale entries (> 60 s old) to avoid navigating to dead calls.
        let age = Date().timeIntervalSince1970 - ts
        result(age < 60 ? callId : nil)

      // Returns the VoIP push payload saved when the call arrived, then clears it.
      // Used by _handleNativeAccept when neither in-memory cache nor secure
      // storage has the call data (VoIP-push path never calls showIncomingCall).
      case "getVoipCallData":
        let callId = call.arguments as? String ?? ""
        let key    = "\(AppDelegate.kVoipPrefix)\(callId)"
        let data   = defaults.dictionary(forKey: key)
        defaults.removeObject(forKey: key)
        result(data)

      // Fallback: returns the raw VoIP (PushKit) token saved in UserDefaults by
      // didUpdate. Used when flutter_callkit_incoming.getDevicePushTokenVoIP()
      // returns null because the plugin sharedInstance was not yet ready when
      // didUpdate fired (engine initialisation race on cold start).
      case "getStoredVoipToken":
        result(defaults.string(forKey: AppDelegate.kVoipToken))

      // Returns (and clears) the full accept snapshot written by onAccept.
      // Contains order_id, caller_name, livekit_url, order_note.
      // This is the most reliable data source — written synchronously at the
      // moment the user taps Accept, before any Dart code runs.
      case "getPendingCallFull":
        // Lowercase for consistent key lookup — onAccept stores with lowercased UUID.
        let callId = (call.arguments as? String ?? "").lowercased()
        let key = "\(AppDelegate.kPendingCallFull)\(callId)"
        let data = defaults.dictionary(forKey: key)
        defaults.removeObject(forKey: key)
        result(data)

      // Restart WebRTC audio engine after a CallKit accept.
      // Mirrors flutter_callkit_incoming's configureAudioSession() +
      // sendDefaultAudioInterruptionNotification() sequence:
      // 1. Re-configure AVAudioSession (category + setActive) so the session
      //    is guaranteed to be active — the main source of intermittent silence
      //    when audio=ok but no sound flows.
      // 2. Post InterruptionNotification(.ended, .shouldResume) so WebRTC's
      //    RTCAudioSession restarts its audio unit.
      case "restartAudio":
        let session = AVAudioSession.sharedInstance()
        do {
          try session.setCategory(
            .playAndRecord,
            options: [.allowBluetooth, .allowBluetoothA2DP, .duckOthers]
          )
          try session.setMode(.voiceChat)
          try session.setActive(true)
        } catch {
          print("[restartAudio] AVAudioSession configure error: \(error)")
        }
        var userInfo: [AnyHashable: Any] = [:]
        userInfo[AVAudioSessionInterruptionTypeKey] =
          AVAudioSession.InterruptionType.ended.rawValue
        userInfo[AVAudioSessionInterruptionOptionKey] =
          AVAudioSession.InterruptionOptions.shouldResume.rawValue
        NotificationCenter.default.post(
          name: AVAudioSession.interruptionNotification,
          object: nil,
          userInfo: userInfo
        )
        result(nil)

      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // Notification tap channel — Dart listens for "onTap" calls and reads
    // "getPendingOrderTap" on cold start to handle taps from killed state.
    let notifChannel = FlutterMethodChannel(
      name: AppDelegate.kNotifChannel,
      binaryMessenger: messenger
    )
    notifChannel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "getPendingOrderTap":
        let orderId = UserDefaults.standard.string(forKey: AppDelegate.kPendingOrder)
        UserDefaults.standard.removeObject(forKey: AppDelegate.kPendingOrder)
        result(orderId)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.notifTapChannel = notifChannel
  }

  // MARK: - CXCallObserverDelegate

  func callObserver(_ callObserver: CXCallObserver, callChanged call: CXCall) {
    // hasConnected transitions to true the moment CallKit considers the call active.
    // Ignore outgoing calls and calls that ended.
    guard !call.isOutgoing, call.hasConnected, !call.hasEnded else { return }
    let callId = call.uuid.uuidString.lowercased()
    // Save kPendingAccept for ALL incoming calls that connect — not just VoIP-push
    // ones. The previous guard (requiring VoIP UserDefaults data) was too strict:
    // for FCM-received calls the data lives only in Dart memory/storage, so the
    // guard would fail after getVoipCallData had already consumed the data.
    // _handleNativeAccept safely ignores callIds it has no data for.
    UserDefaults.standard.set(callId, forKey: AppDelegate.kPendingAccept)
    UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: AppDelegate.kPendingTs)
  }

  // MARK: - CallkitIncomingAppDelegate

  // Called synchronously by the plugin's CXProvider.perform(CXAnswerCallAction)
  // handler — BEFORE any Dart EventChannel event is processed.
  // Snapshot the full call data to UserDefaults so Dart can always find it,
  // regardless of EventChannel timing or isolate state.
  // IMPORTANT: must call action.fulfill() — the plugin skips it when delegate is set.
  func onAccept(_ call: Call, _ action: CXAnswerCallAction) {
    let callId = call.data.uuid.lowercased()
    // Build a plist-safe snapshot (UserDefaults rejects NSNull values).
    var snapshot: [String: Any] = [:]
    if let extras = call.data.extra as? [String: Any] {
      for (k, v) in extras where !(v is NSNull) { snapshot[k] = v }
    }
    snapshot["_call_id"] = callId
    UserDefaults.standard.set(snapshot, forKey: "\(AppDelegate.kPendingCallFull)\(callId)")
    // Mirror kPendingAccept so checkPendingNativeAccept finds it instantly.
    UserDefaults.standard.set(callId, forKey: AppDelegate.kPendingAccept)
    UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: AppDelegate.kPendingTs)
    action.fulfill()
  }

  func onDecline(_ call: Call, _ action: CXEndCallAction) {
    action.fulfill()
  }

  func onEnd(_ call: Call, _ action: CXEndCallAction) {
    action.fulfill()
  }

  func onTimeOut(_ call: Call) {
    // Plugin fulfills the CXEndCallAction itself for timeouts.
  }

  func didActivateAudioSession(_ audioSession: AVAudioSession) {
    // Plugin already calls sendDefaultAudioInterruptionNotification; no extra action needed.
  }

  func didDeactivateAudioSession(_ audioSession: AVAudioSession) {}

  // MARK: - PKPushRegistryDelegate

  func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
    let token = pushCredentials.token.map { String(format: "%02x", $0) }.joined()
    // Always persist to UserDefaults first — this fires before the Flutter engine
    // initialises so the plugin sharedInstance may not be ready yet. Dart reads
    // via getStoredVoipToken as a fallback when getDevicePushTokenVoIP() returns null.
    UserDefaults.standard.set(token, forKey: AppDelegate.kVoipToken)
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP(token)
  }

  func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType, completion: @escaping () -> Void) {
    let dict     = payload.dictionaryPayload
    let callId   = dict["call_id"]    as? String ?? UUID().uuidString
    let callerName = dict["caller_name"] as? String ?? "Cuộc gọi đến"

    // Persist the full VoIP payload so Dart can read orderId/livekitUrl etc.
    // via the getVoipCallData MethodChannel even when the EventChannel event
    // is missed (cold-start race condition).
    UserDefaults.standard.set(dict, forKey: "\(AppDelegate.kVoipPrefix)\(callId)")

    let params: [String: Any] = [
      "id":        callId,
      "nameCaller": callerName,
      "appName":   "Kinme",
      "handle":    "Kinme",
      "type":      0,
      "extra":     dict,
    ]
    guard let plugin = SwiftFlutterCallkitIncomingPlugin.sharedInstance else {
      completion()
      return
    }
    let callData = flutter_callkit_incoming.Data(args: params)
    plugin.showCallkitIncoming(callData, fromPushKit: true, completion: completion)
  }

  func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
    SwiftFlutterCallkitIncomingPlugin.sharedInstance.setDevicePushTokenVoIP("")
  }

  // MARK: - UNUserNotificationCenterDelegate

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    super.userNotificationCenter(center, willPresent: notification, withCompletionHandler: { _ in })
    let userInfo = notification.request.content.userInfo
    // Show ALL notifications in the foreground — both FCM and local.
    // For FCM messages this replaces the previous suppression approach (which
    // relied on flutter_local_notifications re-showing the notification, but that
    // was unreliable on iOS). Tap handling is done in didReceive below via
    // notifTapChannel, which works for both foreground and background taps.
    completionHandler([.banner, .sound, .badge, .list])
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let userInfo = response.notification.request.content.userInfo
    if let orderId = userInfo["order_id"] as? String, !orderId.isEmpty {
      // Always persist — Dart reads this on resume for background→foreground taps.
      UserDefaults.standard.set(orderId, forKey: AppDelegate.kPendingOrder)
      // Invoke directly only when the Flutter engine is already active (foreground tap).
      // For background→foreground taps the engine may not be ready; Dart will read
      // getPendingOrderTap inside didChangeAppLifecycleState(resumed) instead.
      let state = UIApplication.shared.applicationState
      if state == .active || state == .inactive {
        notifTapChannel?.invokeMethod("onTap", arguments: orderId)
      }
    }
    super.userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler)
  }
}
