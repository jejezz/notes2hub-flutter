import Cocoa
import Carbon.HIToolbox
import FlutterMacOS

/// 빠른 메모 전역 단축키(⌃⌥N)의 상태. Carbon 이벤트 콜백은 C 함수라서 값을 붙잡을 수 없어 파일 수준에 둔다.
private var hotKeyRef: EventHotKeyRef?
private var hotKeyHandler: EventHandlerRef?
private var hotKeyChannel: FlutterMethodChannel?

/// 창을 숨기거나 닫아도 앱을 끝내지 않는다 (빠른 메모 단축키를 백그라운드에서 계속 받으려고).
private var keepRunningInBackground = false

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return !keepRunningInBackground
  }

  /// 창을 숨긴 채 백그라운드에서 돌고 있을 때 Dock 아이콘을 누르면 창을 다시 보인다.
  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if !flag {
      mainFlutterWindow?.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
    }
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    if let controller = mainFlutterWindow?.contentViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(name: "notes2hub/hotkey", binaryMessenger: controller.engine.binaryMessenger)
      hotKeyChannel = channel
      channel.setMethodCallHandler { call, result in
        switch call.method {
        case "register": result(registerHotKey())
        case "unregister":
          unregisterHotKey()
          result(nil)
        case "keepRunning":
          keepRunningInBackground = (call.arguments as? Bool) ?? false
          result(nil)
        default: result(FlutterMethodNotImplemented)
        }
      }
    }
    super.applicationDidFinishLaunching(notification)
  }
}

/// ⌃⌥N을 시스템에 등록한다. 다른 앱이 이미 쓰고 있으면 false.
private func registerHotKey() -> Bool {
  unregisterHotKey()
  if hotKeyHandler == nil {
    var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(
      GetApplicationEventTarget(),
      { _, _, _ in
        DispatchQueue.main.async { hotKeyChannel?.invokeMethod("pressed", arguments: nil) }
        return noErr
      }, 1, &spec, nil, &hotKeyHandler)
  }
  let id = EventHotKeyID(signature: OSType(0x4E32_4842), id: 1)  // 'N2HB'
  let status = RegisterEventHotKey(
    UInt32(kVK_ANSI_N), UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0, &hotKeyRef)
  return status == noErr
}

private func unregisterHotKey() {
  if let ref = hotKeyRef {
    UnregisterEventHotKey(ref)
    hotKeyRef = nil
  }
}
