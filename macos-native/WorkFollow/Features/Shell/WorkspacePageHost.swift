import AppKit
import Combine
import SwiftUI

/// Freeze a page's destination while another page is active. In-page links
/// still route through the shared app navigation.
@MainActor
final class WorkspaceNavigationBridge: ObservableObject {
    let navigation: AppNavigation
    private var syncing = false
    private var subscriptions: Set<AnyCancellable> = []

    init(appNavigation: AppNavigation, belongsToPage: @escaping (NativeDestination) -> Bool) {
        navigation = AppNavigation(destination: appNavigation.destination)
        appNavigation.$destination.sink { [weak self] destination in
            guard let self, !self.syncing, belongsToPage(destination),
                  self.navigation.destination != destination else { return }
            self.syncing = true
            self.navigation.destination = destination
            self.syncing = false
        }.store(in: &subscriptions)
        navigation.$destination.dropFirst().sink { [weak self, weak appNavigation] destination in
            guard let self, let appNavigation, !self.syncing,
                  belongsToPage(appNavigation.destination),
                  appNavigation.destination != destination else { return }
            self.syncing = true
            appNavigation.destination = destination
            self.syncing = false
        }.store(in: &subscriptions)
    }
}

/// Pages are created on first visit. Detaching the inactive host preserves its
/// controls and view state while keeping it outside window layout and focus.
@MainActor
final class WorkspacePageCache: ObservableObject {
    #if DEBUG
    enum Diagnostics {
        static var createdHosts = 0
        static var rootAssignments = 0
        static var attachments = 0
        static var detachments = 0
        static var showTime: TimeInterval = 0
        static func reset() {
            createdHosts = 0; rootAssignments = 0; attachments = 0; detachments = 0; showTime = 0
        }
    }
    #endif
    /// 任务页常驻后每页约占 13–18MB（实测 7 个清单页 RSS 66MB → 约 190MB）。
    /// 只保留最近访问的几页，回访淘汰页时按首次进入重建。
    static let mountedPageLimit = 4

    private var hosts: [String: NSHostingView<AnyView>] = [:]
    private var signatures: [String: String] = [:]
    private var navigationBridges: [String: WorkspaceNavigationBridge] = [:]

    /// 宿主已从容器卸下：同时丢弃缓存，避免下次回访把脱管视图重新挂上。
    func evict(_ key: String) {
        hosts.removeValue(forKey: key)
        signatures.removeValue(forKey: key)
    }

    func navigation(for key: String, appNavigation: AppNavigation,
                    belongsToPage: @escaping (NativeDestination) -> Bool) -> AppNavigation {
        if let bridge = navigationBridges[key] { return bridge.navigation }
        let bridge = WorkspaceNavigationBridge(appNavigation: appNavigation, belongsToPage: belongsToPage)
        navigationBridges[key] = bridge
        return bridge.navigation
    }

    /// 无签名调用保持旧行为（每次替换 rootView），供测试直接驱动缓存。
    func host(for key: String, content: AnyView) -> NSHostingView<AnyView> {
        host(for: key, signature: nil, content: content)
    }

    /// 内容签名没变时不重设 `rootView`：页面靠 @ObservedObject 自行刷新，
    /// 重设会让整页 SwiftUI 图重新求值，实测一次切页多花约 150ms。
    func host(for key: String, signature: String?, content: AnyView) -> NSHostingView<AnyView> {
        if let host = hosts[key] {
            if let signature, signatures[key] != signature {
                #if DEBUG
                Diagnostics.rootAssignments += 1
                #endif
                host.rootView = content
                signatures[key] = signature
            } else if signature == nil {
                #if DEBUG
                Diagnostics.rootAssignments += 1
                #endif
                host.rootView = content
            }
            return host
        }
        let host = NSHostingView(rootView: content)
        #if DEBUG
        Diagnostics.createdHosts += 1
        #endif
        // The outer shell owns window safe areas and the traffic-light inset.
        // A nested host would otherwise add the titlebar inset again.
        host.safeAreaRegions = []
        host.sizingOptions = []
        hosts[key] = host
        if let signature { signatures[key] = signature }
        return host
    }
}

struct WorkspacePageHost: NSViewRepresentable {
    let cache: WorkspacePageCache
    let pageKey: String
    let contentSignature: String
    /// 任务列页面常驻：切智能清单只切显示，不卸载宿主。
    var keepsMounted = false
    let content: AnyView

    func makeNSView(context: Context) -> Container { Container(cache: cache) }

    func updateNSView(_ container: Container, context: Context) {
        container.show(cache.host(for: pageKey, signature: contentSignature, content: content),
                       key: pageKey, keepsMounted: keepsMounted)
    }

    static func dismantleNSView(_ container: Container, coordinator: ()) {
        container.detach()
    }

    final class Container: NSView {
        private(set) var currentHost: NSHostingView<AnyView>?
        /// 常驻宿主按页面 key 保存；切到非任务页时统一卸载，保留原有的
        /// onDisappear 清理语义（笔记保存、会议停录音等）。
        private var mountedHosts: [String: NSHostingView<AnyView>] = [:]
        /// 最近访问顺序，只用于淘汰最久未看的常驻页。
        private var mountOrder: [String] = []
        private var currentIsMounted = false
        private weak var cache: WorkspacePageCache?

        init(cache: WorkspacePageCache? = nil) {
            self.cache = cache
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        func detach() {
            for host in mountedHosts.values { host.removeFromSuperview() }
            mountedHosts.removeAll()
            mountOrder.removeAll()
            currentHost?.removeFromSuperview()
            currentHost = nil
            currentIsMounted = false
        }

        func show(_ host: NSHostingView<AnyView>, key: String = "", keepsMounted: Bool = false) {
            #if DEBUG
            let started = ProcessInfo.processInfo.systemUptime
            defer { WorkspacePageCache.Diagnostics.showTime += ProcessInfo.processInfo.systemUptime - started }
            #endif
            if keepsMounted {
                if currentHost === host, currentIsMounted, !host.isHidden {
                    touch(key)
                    return
                }
                resignFirstResponderIfNeeded()
                if let currentHost, currentHost !== host {
                    if currentIsMounted { currentHost.isHidden = true }
                    else { remove(currentHost) }
                }
                attachIfNeeded(host)
                for mounted in mountedHosts.values where mounted !== host { mounted.isHidden = true }
                host.isHidden = false
                mountedHosts[key] = host
                touch(key)
                evictOverflow(keeping: key)
                currentHost = host
                currentIsMounted = true
                return
            }

            // 离开任务列：把常驻的任务页宿主全部卸下，让各自的生命周期回调生效。
            if !mountedHosts.isEmpty {
                resignFirstResponderIfNeeded()
                for mounted in mountedHosts.values { remove(mounted) }
                let stale = mountOrder.dropLast(WorkspacePageCache.mountedPageLimit)
                mountedHosts.removeAll()
                mountOrder.removeAll()
                for key in stale { cache?.evict(key) }
                currentHost = nil
                currentIsMounted = false
            }
            guard currentHost !== host else {
                attachIfNeeded(host)
                currentIsMounted = false
                return
            }
            resignFirstResponderIfNeeded()
            if let currentHost { remove(currentHost) }
            attachIfNeeded(host)
            currentHost = host
            currentIsMounted = false
        }

        private func touch(_ key: String) {
            mountOrder.removeAll { $0 == key }
            mountOrder.append(key)
        }

        private func evictOverflow(keeping key: String) {
            while mountedHosts.count > WorkspacePageCache.mountedPageLimit {
                guard let victim = mountOrder.first(where: { $0 != key && mountedHosts[$0] != nil }) else { return }
                mountedHosts.removeValue(forKey: victim)?.removeFromSuperview()
                mountOrder.removeAll { $0 == victim }
                cache?.evict(victim)
            }
        }

        private func attachIfNeeded(_ host: NSHostingView<AnyView>) {
            guard host.superview !== self else { return }
            #if DEBUG
            WorkspacePageCache.Diagnostics.attachments += 1
            #endif
            host.translatesAutoresizingMaskIntoConstraints = false
            addSubview(host)
            NSLayoutConstraint.activate([
                host.leadingAnchor.constraint(equalTo: leadingAnchor),
                host.trailingAnchor.constraint(equalTo: trailingAnchor),
                host.topAnchor.constraint(equalTo: topAnchor),
                host.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }

        private func remove(_ host: NSHostingView<AnyView>) {
            #if DEBUG
            if host.superview != nil { WorkspacePageCache.Diagnostics.detachments += 1 }
            #endif
            host.removeFromSuperview()
        }

        /// 隐藏/卸载前必须交还键盘焦点，否则输入会继续落到看不见的页面上。
        private func resignFirstResponderIfNeeded() {
            guard let responder = window?.firstResponder as? NSView else { return }
            var hosts = Array(mountedHosts.values)
            if let currentHost { hosts.append(currentHost) }
            if hosts.contains(where: { responder.isDescendant(of: $0) }) {
                window?.makeFirstResponder(nil)
            }
        }
    }
}
