import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController.init()
    let windowFrame = self.frame

    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // 제목 표시줄 투명하게 설정
    self.titlebarAppearsTransparent = true
    self.backgroundColor = NSColor.clear // 배경색도 투명하게 설정 (선택 사항)
    self.isOpaque = false // 창을 불투명하게 만들지 않음 (선택 사항)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}