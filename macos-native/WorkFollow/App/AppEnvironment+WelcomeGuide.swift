import AppKit

enum WelcomeGuideEnsureResult: Equatable {
    case none
    case seeded
    case upgraded
}

extension AppEnvironment {
    private var welcomeGuideDefaultsKey: String {
        "welcomeGuide.installed." + NativePreviewRepository.directory.path
    }

    private var welcomeGuideWelcomeShownKey: String {
        "welcomeGuide.welcomeShown." + NativePreviewRepository.directory.path
    }

    /// 首次启动种入「👋欢迎」；用户删掉后不会自动复活，重置入口负责恢复。
    /// 只对全新空库弹一次欢迎页，老用户升级静默种入。
    @discardableResult
    func ensureWelcomeGuideIfNeeded(defaults: UserDefaults = .standard,
                                    allowInTests: Bool = false) -> WelcomeGuideEnsureResult {
        guard canSeedWelcomeGuide else { return .none }
        // Unit-test hosts launch the app too; never let fixtures inherit a seeded guide.
        if !allowInTests {
            guard NSClassFromString("XCTestCase") == nil,
                  !ProcessInfo.processInfo.arguments.contains("--wf-skip-welcome-guide") else { return .none }
        }
        let key = welcomeGuideDefaultsKey
        guard defaults.integer(forKey: key) < WelcomeGuide.version else { return .none }

        if taskWorkspace.allTasks.contains(where: { $0.guideAction != nil }) {
            let upgraded = taskWorkspace.upgradeWelcomeGuide()
            defaults.set(WelcomeGuide.version, forKey: key)
            return upgraded ? .upgraded : .none
        }
        if taskWorkspace.listNames.contains(WelcomeGuide.listName) {
            defaults.set(WelcomeGuide.version, forKey: key)
            return .none
        }

        let isFirstLaunch = !hadStoredWorkspace
            && !defaults.bool(forKey: welcomeGuideWelcomeShownKey)
        guard taskWorkspace.installWelcomeGuide() else { return .none }
        defaults.set(WelcomeGuide.version, forKey: key)
        if isFirstLaunch {
            defaults.set(true, forKey: welcomeGuideWelcomeShownKey)
            welcomeGuideWelcomePresented = true
        }
        return .seeded
    }

    /// 帮助菜单入口：引导任务还在就打开清单，被删了就确认后重建。
    func showWelcomeGuide() {
        NativeMainWindowPresenter.activate()
        if taskWorkspace.allTasks.contains(where: { $0.guideAction != nil }),
           taskWorkspace.listNames.contains(WelcomeGuide.listName) {
            openWelcomeGuide()
        } else {
            resetWelcomeGuide()
        }
    }

    func resetWelcomeGuide() {
        NativeMainWindowPresenter.activate()
        let alert = NSAlert()
        alert.messageText = "重新生成「\(WelcomeGuide.listName)」新手引导？"
        alert.informativeText = "会删除引导任务和勾选进度（含其子任务），并重新种入 "
            + "\(WelcomeGuide.items.count) 条引导；你在该清单里自己添加的任务会保留。"
        alert.addButton(withTitle: "重新生成")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        if taskWorkspace.resetWelcomeGuide() {
            UserDefaults.standard.set(WelcomeGuide.version, forKey: welcomeGuideDefaultsKey)
            openWelcomeGuide()
            feedback.show(FeedbackEvent(kind: .info, message: "新手引导已重建"))
        } else {
            feedback.show(FeedbackEvent(kind: .error, message: "新手引导重建失败"))
        }
    }

    /// 只选择「👋欢迎」清单；清单被删除时退回所有任务，不偷偷重建。
    func openWelcomeGuide() {
        navigation.taskSelectionToPreserveOnNextNavigation = nil
        taskWorkspace.activeList = taskWorkspace.listNames.contains(WelcomeGuide.listName)
            ? WelcomeGuide.listName : nil
        taskWorkspace.activeTag = nil
        taskWorkspace.openFilter(nil)
        taskWorkspace.clearBulkSelection()
        taskWorkspace.select(nil)
        navigation.destination = .allTasks
        NativeMainWindowPresenter.activate()
    }

    func openGuideAction(_ action: WelcomeGuide.Action) -> Bool {
        switch action {
        case .quickAdd:
            if navigation.destination.isNotes { navigation.destination = .today }
            newTask()
        case .schedule, .complete:
            navigate(to: .today)
        case .list:
            openWelcomeGuide()
        case .matrix:
            navigate(to: .matrix)
        case .calendar:
            navigate(to: .calendar)
        case .focus:
            navigate(to: .focus)
        case .meetings:
            navigate(to: .meetings)
        case .notes:
            navigate(to: .notes)
        case .floatingNote:
            return newFloatingNote() != nil
        case .allTasks:
            navigation.taskSelectionToPreserveOnNextNavigation = nil
            taskWorkspace.activeList = nil
            taskWorkspace.activeTag = nil
            taskWorkspace.openFilter(nil)
            taskWorkspace.select(nil)
            navigate(to: .allTasks)
        case .summary:
            navigate(to: .summary)
        case .commandPalette:
            commandPalettePresented = true
        case .agentAccess, .aiConfiguration:
            if action == .aiConfiguration { settingsSection = .ai }
            openWelcomeGuide()
            if let task = taskWorkspace.allTasks.first(where: {
                $0.guideAction == action.rawValue && $0.deletedAt == nil
            }) {
                taskWorkspace.select(task.id)
            }
        }
        NativeMainWindowPresenter.activate()
        return true
    }
}
