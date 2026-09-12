import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // The unified rail plus list/detail panes stay usable down to the
    // smallest validated layout (880x600); below that the detail falls back
    // to a single pane with a back path.
    self.minSize = NSSize(width: 880, height: 600)
    let defaultSize = NSSize(width: 1280, height: 820)
    let visibleFrame = NSScreen.main?.visibleFrame
    let fittedSize = NSSize(
      width: min(defaultSize.width, (visibleFrame?.width ?? defaultSize.width) * 0.9),
      height: min(defaultSize.height, (visibleFrame?.height ?? defaultSize.height) * 0.9)
    )
    let isStarterFrame =
      (self.frame.width <= 800 && self.frame.height <= 600) ||
      (self.frame.width == defaultSize.width && self.frame.height == defaultSize.height)
    if isStarterFrame {
      self.setContentSize(fittedSize)
      self.center()
    }

    let platformChannel = FlutterMethodChannel(
      name: "workfollow/platform",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    platformChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "pickMigrationFile":
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedFileTypes = ["json", "workfollow"]
        panel.title = "选择打勾个人数据文件"
        panel.message = "请选择从 Web 端导出的 .workfollow.json 文件"
        result(panel.runModal() == .OK ? panel.url?.path : nil)
      case "applicationSupportDirectory":
        let fileManager = FileManager.default
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent("WorkFollow", isDirectory: true)
        do {
          try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
          result(directory.path)
        } catch {
          result(FlutterError(
            code: "application_support_unavailable",
            message: "无法创建本地数据目录",
            details: error.localizedDescription
          ))
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
