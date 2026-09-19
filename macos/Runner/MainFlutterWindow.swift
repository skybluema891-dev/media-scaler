import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func becomeKey() {
    super.becomeKey()
    // Apply after launch/restoration has supplied the default application title.
    DispatchQueue.main.async { [weak self] in
      if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
         !version.isEmpty {
        self?.title = "メディア・スケーラー v\(version)"
      }
    }
  }

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // Start with the file drop area on the left and settings on the right.
    // HomeScreen switches to the stacked layout below 900 logical pixels.
    if let visibleFrame = (self.screen ?? NSScreen.main)?.visibleFrame {
      let titleBarHeight = self.frame.height - self.contentLayoutRect.height
      self.setContentSize(NSSize(
        width: min(1000, visibleFrame.width),
        height: min(800, visibleFrame.height - titleBarHeight)
      ))
    } else {
      self.setContentSize(NSSize(width: 1000, height: 800))
    }
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
