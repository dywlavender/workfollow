import Cocoa
import FlutterMacOS
import UserNotifications
import Carbon.HIToolbox

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
      case "pickAttachmentFile":
        // The powerbox grant lets the sandboxed app read the picked file so
        // Dart can copy it into the container's attachments folder.
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = "选择要附加的文件"
        result(panel.runModal() == .OK ? panel.url?.path : nil)
      case "revealInFinder":
        guard let args = call.arguments as? [String: Any],
              let path = args["path"] as? String else {
          result(false)
          return
        }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let notificationChannel = FlutterMethodChannel(
      name: "workfollow/notifications",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    let notificationManager = NotificationManager(channel: notificationChannel)
    notificationChannel.setMethodCallHandler { [weak notificationManager] call, result in
      notificationManager?.handle(call, result: result)
    }
    // UNUserNotificationCenter.delegate is weak; the association keeps the
    // manager alive for the window's lifetime.
    objc_setAssociatedObject(self, &NotificationManager.associatedKey,
                             notificationManager, .OBJC_ASSOCIATION_RETAIN)

    // Menu bar quick capture: status item + a global hotkey that opens a
    // non-activating panel, so the previous app keeps focus.
    let captureChannel = FlutterMethodChannel(
      name: "workfollow/capture",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    let captureController = CapturePanelController(channel: captureChannel)
    captureController.registerGlobalHotkey()
    GlobalCapture.shared.panelController = captureController
    GlobalCapture.shared.mainWindow = self
    objc_setAssociatedObject(self, &CapturePanelController.associatedKey,
                             captureController, .OBJC_ASSOCIATION_RETAIN)
    installStatusItem(captureController: captureController)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }

  // MARK: - Menu bar status item

  private var statusItem: NSStatusItem?

  private func installStatusItem(captureController: CapturePanelController) {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    if #available(macOS 11.0, *) {
      item.button?.image = NSImage(systemSymbolName: "checkmark.circle",
                                   accessibilityDescription: "打勾菜单栏")
    } else {
      item.button?.title = "勾"
    }
    let menu = NSMenu()
    let captureEntry = NSMenuItem(title: "快速录入",
                                  action: #selector(CapturePanelController.togglePanel),
                                  keyEquivalent: "")
    captureEntry.target = captureController
    menu.addItem(captureEntry)
    let openEntry = NSMenuItem(title: "显示打勾",
                               action: #selector(MainFlutterWindow.showMainWindow),
                               keyEquivalent: "")
    openEntry.target = self
    menu.addItem(openEntry)
    menu.addItem(.separator())
    menu.addItem(withTitle: "退出打勾",
                 action: #selector(NSApplication.terminate(_:)),
                 keyEquivalent: "")
    item.menu = menu
    statusItem = item
  }

  @objc func showMainWindow() {
    NSApp.activate(ignoringOtherApps: true)
    makeKeyAndOrderFront(nil)
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

/// Schedules task reminders as system notifications and reports clicks back
/// to Dart. Identifiers are derived from task ids so rescheduling replaces
/// the pending request instead of duplicating it.
class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
  nonisolated(unsafe) static var associatedKey = "notification_manager"

  private let channel: FlutterMethodChannel

  init(channel: FlutterMethodChannel) {
    self.channel = channel
    super.init()
    UNUserNotificationCenter.current().delegate = self
  }

  static func identifier(for taskId: String) -> String {
    return "reminder-\(taskId)"
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "requestPermission":
      let center = UNUserNotificationCenter.current()
      center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
        result(granted)
      }
    case "authorizationStatus":
      let center = UNUserNotificationCenter.current()
      center.getNotificationSettings { settings in
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
          result("authorized")
        case .denied:
          result("denied")
        default:
          result("notDetermined")
        }
      }
    case "schedule":
      guard
        let args = call.arguments as? [String: Any],
        let taskId = args["taskId"] as? String,
        let title = args["title"] as? String,
        let fireAtMillis = (args["fireAtMillis"] as? NSNumber)?.intValue
      else {
        result(FlutterError(code: "bad_arguments",
                            message: "schedule 需要 taskId/title/fireAtMillis",
                            details: nil))
        return
      }
      let content = UNMutableNotificationContent()
      content.title = title
      if let body = args["body"] as? String, !body.isEmpty {
        content.body = body
      }
      content.sound = .default
      content.userInfo = ["taskId": taskId]
      let fireDate = Date(timeIntervalSince1970: Double(fireAtMillis) / 1000.0)
      let components = Calendar.current.dateComponents(
        [.year, .month, .day, .hour, .minute], from: fireDate)
      let trigger = UNCalendarNotificationTrigger(dateMatching: components,
                                                  repeats: false)
      let request = UNNotificationRequest(
        identifier: NotificationManager.identifier(for: taskId),
        content: content,
        trigger: trigger)
      UNUserNotificationCenter.current().add(request) { error in
        result(error == nil)
      }
    case "cancel":
      guard
        let args = call.arguments as? [String: Any],
        let taskId = args["taskId"] as? String
      else {
        result(false)
        return
      }
      UNUserNotificationCenter.current().removePendingNotificationRequests(
        withIdentifiers: [NotificationManager.identifier(for: taskId)])
      result(true)
    case "cancelAll":
      UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
      result(true)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    // Show the banner even while the app is in the foreground.
    if #available(macOS 12.0, *) {
      completionHandler([.banner, .sound])
    } else {
      completionHandler([.alert, .sound])
    }
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    if let taskId = response.notification.request.content.userInfo["taskId"]
      as? String {
      channel.invokeMethod("notificationClicked", arguments: taskId)
    }
    completionHandler()
  }
}

/// Application-wide handles the Carbon hotkey callback can reach (C function
/// pointers cannot capture context).
final class GlobalCapture {
  static let shared = GlobalCapture()
  weak var panelController: CapturePanelController?
  weak var mainWindow: MainFlutterWindow?
}

/// The lightweight quick-capture panel. Non-activating by design: it takes
/// key focus without stealing the previous app's active status, and closes
/// on Return (saving) or Escape (cancelling).
final class CapturePanelController: NSObject, NSTextFieldDelegate {
  nonisolated(unsafe) static var associatedKey = "capture_panel_controller"

  private let channel: FlutterMethodChannel
  private var panel: NSPanel?
  private weak var inputField: NSTextField?
  private var hotKeyRef: EventHotKeyRef?

  init(channel: FlutterMethodChannel) {
    self.channel = channel
  }

  /// ⇧⌘Space. RegisterEventHotKey works inside the sandbox and does not ask
  /// for Input Monitoring permission.
  func registerGlobalHotkey() {
    var hotKeyID = EventHotKeyID(signature: OSType(0x44434B47) /* 'DCKG' */, id: 1)
    var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                  eventKind: UInt32(kEventHotKeyPressed))
    let selfPtr = Unmanaged.passUnretained(self).toOpaque()
    InstallEventHandler(GetApplicationEventTarget(), { _, _, userData -> OSStatus in
      guard let controller = Unmanaged<CapturePanelController>
              .fromOpaque(userData!).takeUnretainedValue() as CapturePanelController? else {
        return OSStatus(eventNotHandledErr)
      }
      controller.togglePanel()
      return noErr
    }, 1, &eventType, selfPtr, nil)
    // kVK_ANSI_Space = 49; shiftKey = 0x0200, cmdKey = 0x0100.
    let status = RegisterEventHotKey(UInt32(49),
                                     UInt32(0x0300),
                                     hotKeyID,
                                     GetApplicationEventTarget(),
                                     0,
                                     &hotKeyRef)
    if status != noErr {
      NSLog("quick capture hotkey registration failed: \(status)")
    }
    hotKeyID.id = 1 // keep the value alive for the ref above
  }

  @objc func togglePanel() {
    if panel?.isVisible == true {
      hidePanel()
    } else {
      showPanel()
    }
  }

  private func showPanel() {
    let target = panel ?? makePanel()
    panel = target
    if let screen = NSScreen.main {
      let frame = target.frame
      let origin = NSPoint(
        x: screen.visibleFrame.midX - frame.width / 2,
        y: screen.visibleFrame.maxY - frame.height - 140)
      target.setFrameOrigin(origin)
    }
    target.makeKeyAndOrderFront(nil)
    inputField?.becomeFirstResponder()
  }

  private func hidePanel() {
    panel?.orderOut(nil)
  }

  private func makePanel() -> NSPanel {
    let panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 540, height: 52),
      styleMask: [.titled, .nonactivatingPanel, .utilityWindow],
      backing: .buffered,
      defer: false)
    panel.titleVisibility = .hidden
    panel.titlebarAppearsTransparent = true
    panel.isMovableByWindowBackground = false
    panel.level = .floating
    panel.isFloatingPanel = true
    panel.hidesOnDeactivate = false
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

    let field = NSTextField(frame: NSRect(x: 14, y: 15, width: 512, height: 22))
    field.placeholderString = "记下下一件事，Return 保存到收集箱，Esc 取消"
    field.font = NSFont.systemFont(ofSize: 15)
    field.isBordered = false
    field.isBezeled = false
    field.drawsBackground = false
    field.focusRingType = .none
    field.delegate = self
    panel.contentView?.addSubview(field)
    self.panel = panel
    self.inputField = field
    return panel
  }

  func control(_ control: NSControl, textView: NSTextView,
               doCommandBy commandSelector: Selector) -> Bool {
    switch commandSelector {
    case #selector(NSResponder.insertNewline(_:)):
      submit()
      return true
    case #selector(NSResponder.cancelOperation(_:)):
      hidePanel()
      return true
    default:
      return false
    }
  }

  private func submit() {
    guard let field = inputField else { return }
    let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else {
      hidePanel()
      return
    }

    // Let Dart confirm the write before clearing the field. If persistence or
    // the platform channel fails, the panel stays open and the user's text is
    // still available for another attempt.
    channel.invokeMethod("quickCapture", arguments: text) { [weak self] response in
      DispatchQueue.main.async {
        guard let self, let field = self.inputField else { return }
        if let error = response as? FlutterError {
          NSLog("quick capture failed: \(error.message ?? error.code)")
          return
        }
        guard (response as? Bool) == true else {
          NSSound.beep()
          return
        }
        field.stringValue = ""
        self.hidePanel()
      }
    }
  }
}
