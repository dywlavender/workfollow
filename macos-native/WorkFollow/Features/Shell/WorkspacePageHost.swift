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
    private var hosts: [String: NSHostingView<AnyView>] = [:]
    private var navigationBridges: [String: WorkspaceNavigationBridge] = [:]

    func navigation(for key: String, appNavigation: AppNavigation,
                    belongsToPage: @escaping (NativeDestination) -> Bool) -> AppNavigation {
        if let bridge = navigationBridges[key] { return bridge.navigation }
        let bridge = WorkspaceNavigationBridge(appNavigation: appNavigation, belongsToPage: belongsToPage)
        navigationBridges[key] = bridge
        return bridge.navigation
    }

    func host(for key: String, content: AnyView) -> NSHostingView<AnyView> {
        if let host = hosts[key] {
            host.rootView = content
            return host
        }
        let host = NSHostingView(rootView: content)
        host.sizingOptions = []
        hosts[key] = host
        return host
    }
}

struct WorkspacePageHost: NSViewRepresentable {
    let cache: WorkspacePageCache
    let pageKey: String
    let content: AnyView

    func makeNSView(context: Context) -> Container { Container() }

    func updateNSView(_ container: Container, context: Context) {
        container.show(cache.host(for: pageKey, content: content))
    }

    static func dismantleNSView(_ container: Container, coordinator: ()) {
        container.detach()
    }

    final class Container: NSView {
        private(set) var currentHost: NSHostingView<AnyView>?

        func detach() {
            currentHost?.removeFromSuperview()
            currentHost = nil
        }

        func show(_ host: NSHostingView<AnyView>) {
            guard currentHost !== host else { return }
            if let responder = window?.firstResponder as? NSView,
               let currentHost, responder.isDescendant(of: currentHost) {
                window?.makeFirstResponder(nil)
            }
            currentHost?.removeFromSuperview()
            currentHost = host
            host.translatesAutoresizingMaskIntoConstraints = false
            addSubview(host)
            NSLayoutConstraint.activate([
                host.leadingAnchor.constraint(equalTo: leadingAnchor),
                host.trailingAnchor.constraint(equalTo: trailingAnchor),
                host.topAnchor.constraint(equalTo: topAnchor),
                host.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }
    }
}
