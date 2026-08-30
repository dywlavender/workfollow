import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

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
