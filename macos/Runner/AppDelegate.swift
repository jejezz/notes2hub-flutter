import Cocoa
import Carbon.HIToolbox
import FlutterMacOS

/// 빠른 메모 전역 단축키(⌃⌥N)의 상태. Carbon 이벤트 콜백은 C 함수라서 값을 붙잡을 수 없어 파일 수준에 둔다.
private var hotKeyRef: EventHotKeyRef?
private var hotKeyHandler: EventHandlerRef?
private var hotKeyChannel: FlutterMethodChannel?

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
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
