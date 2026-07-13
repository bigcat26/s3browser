import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    // 最小窗口尺寸: 720x500. 低于这个宽度 AppBar 5 actions + title 装不下,
    // 状态栏 3 段 label 撑爆, 文件列表 date/size 列也溢出.
    if let window = NSApp.windows.first {
      window.minSize = NSSize(width: 720, height: 500)
    }
  }
}
