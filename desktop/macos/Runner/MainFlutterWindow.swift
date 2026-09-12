import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private static let savedFrameKey = "WorkFollowWindowFrame"

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // The unified rail plus list/detail panes stay usable down to the
    // smallest validated layout (880x600); below that the detail falls back
    // to a single pane with a back path.
    self.minSize = NSSize(width: 880, height: 600)

    restoreOrCreateFrame()
    registerFrameObservers()
    installMainMenu(channelName: "workfollow/menu",
                    messenger: flutterViewController.engine.binaryMessenger)

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

  // MARK: - Window frame persistence

  private func restoreOrCreateFrame() {
    let defaults = UserDefaults.standard
    if let saved = defaults.string(forKey: Self.savedFrameKey) {
      let restored = NSRectFromString(saved)
      // Only restore frames that are still on a connected display.
      if restored != .zero,
         NSScreen.screens.contains(where: { $0.visibleFrame.intersects(restored) }) {
        self.setFrame(restored, display: false)
        return
      }
    }
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
  }

  private func registerFrameObservers() {
    let center = NotificationCenter.default
    center.addObserver(forName: NSWindow.didEndLiveResizeNotification,
                       object: self, queue: .main) { [weak self] _ in
      self?.saveFrame()
    }
    center.addObserver(forName: NSWindow.didMoveNotification,
                       object: self, queue: .main) { [weak self] _ in
      self?.saveFrame()
    }
  }

  private func saveFrame() {
    UserDefaults.standard.set(
      NSStringFromRect(self.frame),
      forKey: Self.savedFrameKey
    )
  }

  // MARK: - Native command menu

  /// Builds the menu bar. Command items route through the "workfollow/menu"
  /// channel so Dart owns the behavior exactly as it does for the in-app
  /// keyboard shortcuts; Edit items target the responder chain so text
  /// fields get the standard clipboard behavior.
  private func installMainMenu(channelName: String, messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    let commandTarget = MenuCommandTarget(channel: channel)
    objc_setAssociatedObject(self, &MenuCommandTarget.associatedKey, commandTarget,
                             .OBJC_ASSOCIATION_RETAIN)

    let mainMenu = NSMenu()

    // App menu
    let appMenuItem = NSMenuItem()
    mainMenu.addItem(appMenuItem)
    let appMenu = NSMenu(title: "打勾")
    appMenu.addItem(withTitle: "关于打勾",
                    action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                    keyEquivalent: "")
    appMenu.addItem(.separator())
    appMenu.addCommand("设置…", key: ",", command: "settings", target: commandTarget)
    appMenu.addItem(.separator())
    appMenu.addItem(withTitle: "退出打勾",
                    action: #selector(NSApplication.terminate(_:)),
                    keyEquivalent: "q")
    appMenuItem.submenu = appMenu

    // File menu
    let fileMenuItem = NSMenuItem()
    mainMenu.addItem(fileMenuItem)
    let fileMenu = NSMenu(title: "文件")
    fileMenu.addCommand("新建任务", key: "n", command: "newTask", target: commandTarget)
    fileMenu.addCommand("新建笔记", key: "n", modifiers: [.command, .shift],
                        command: "newNote", target: commandTarget)
    fileMenu.addItem(.separator())
    fileMenu.addCommand("搜索", key: "k", command: "search", target: commandTarget)
    fileMenuItem.submenu = fileMenu

    // Edit menu: standard responder-chain selectors for text fields.
    let editMenuItem = NSMenuItem()
    mainMenu.addItem(editMenuItem)
    let editMenu = NSMenu(title: "编辑")
    editMenu.addItem(withTitle: "剪切",
                     action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    editMenu.addItem(withTitle: "拷贝",
                     action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    editMenu.addItem(withTitle: "粘贴",
                     action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    editMenu.addItem(withTitle: "全选",
                     action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    editMenuItem.submenu = editMenu

    // View menu: the destinations users reach with Cmd-1..5.
    let viewMenuItem = NSMenuItem()
    mainMenu.addItem(viewMenuItem)
    let viewMenu = NSMenu(title: "视图")
    viewMenu.addCommand("今天", key: "1", command: "goToday", target: commandTarget)
    viewMenu.addCommand("收集箱", key: "2", command: "goInbox", target: commandTarget)
    viewMenu.addCommand("计划", key: "3", command: "goPlan", target: commandTarget)
    viewMenu.addCommand("日历", key: "4", command: "goCalendar", target: commandTarget)
    viewMenu.addCommand("笔记", key: "5", command: "goNotes", target: commandTarget)
    viewMenu.addItem(.separator())
    viewMenu.addCommand("显示或隐藏侧栏", key: "\\", command: "toggleSidebar",
                        target: commandTarget)
    viewMenuItem.submenu = viewMenu

    // Window menu
    let windowMenuItem = NSMenuItem()
    mainMenu.addItem(windowMenuItem)
    let windowMenu = NSMenu(title: "窗口")
    windowMenu.addItem(withTitle: "最小化",
                       action: #selector(NSWindow.performMiniaturize(_:)),
                       keyEquivalent: "m")
    windowMenu.addItem(withTitle: "缩放",
                       action: #selector(NSWindow.performZoom(_:)),
                       keyEquivalent: "")
    windowMenuItem.submenu = windowMenu
    NSApp.windowsMenu = windowMenu

    NSApp.mainMenu = mainMenu
  }
}

/// Forwards menu commands to Dart over the menu channel. The window keeps a
/// retained reference via objc_setAssociatedObject so the target outlives
/// awakeFromNib.
class MenuCommandTarget: NSObject {
  nonisolated(unsafe) static var associatedKey = "menu_command_target"

  private let channel: FlutterMethodChannel

  init(channel: FlutterMethodChannel) {
    self.channel = channel
  }

  @objc func sendCommand(_ sender: NSMenuItem) {
    guard let command = sender.representedObject as? String else { return }
    channel.invokeMethod("command", arguments: command)
  }
}

private extension NSMenu {
  func addCommand(_ title: String, key: String,
                  modifiers: NSEvent.ModifierFlags = .command,
                  command: String,
                  target: MenuCommandTarget) {
    let item = NSMenuItem(title: title,
                          action: #selector(MenuCommandTarget.sendCommand(_:)),
                          keyEquivalent: key)
    item.keyEquivalentModifierMask = modifiers
    item.target = target
    item.representedObject = command
    addItem(item)
  }
}
