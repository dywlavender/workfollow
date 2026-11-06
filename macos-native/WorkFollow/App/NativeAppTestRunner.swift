import AppKit

#if DEBUG && WORKFOLLOW_APP_TEST_HOST
import XCTest
import ObjectiveC.runtime
#endif

/// XCTest runs inside the real signed App, so body tests use the same WebKit host.
/// This entry is compiled only by run-tests.sh and requires disposable storage.
@MainActor
enum NativeAppTestRunner {
    private(set) static var isRunning = false
    static func runIfRequested() -> Bool {
        #if DEBUG && WORKFOLLOW_APP_TEST_HOST
        let args = ProcessInfo.processInfo.arguments
        guard let position = args.firstIndex(of: "--wf-xctest"), args.indices.contains(position + 1),
              let root = Bundle.main.object(forInfoDictionaryKey: "WorkFollowAcceptanceStorageRoot") as? String,
              !root.isEmpty else { return false }
        let path = args[position + 1]
        isRunning = true
        let selected: [String]
        if let index = args.firstIndex(of: "--wf-test-classes"), args.indices.contains(index + 1) {
            selected = args[index + 1].split(separator: ",").map(String.init)
        } else { selected = [] }
        // XCTest pumps a nested run loop while awaiting async @MainActor tests.
        // Start from a run-loop timer, not the main dispatch queue: a dispatch
        // callback cannot reenter that queue to start the test's async body.
        Timer.scheduledTimer(withTimeInterval: 0.01, repeats: false) { _ in
            MainActor.assumeIsolated {
            do {
                guard let bundle = Bundle(path: path) else { throw AIBackendError.failed("找不到 XCTest 包。") }
                try bundle.loadAndReturnError()
                let owner = NSWindow(contentRect: NSRect(x: -2000, y: -2000, width: 1, height: 1),
                                     styleMask: [.borderless], backing: .buffered, defer: false)
                owner.isReleasedWhenClosed = false
                owner.orderBack(nil)
                let suite = XCTestSuite(name: "WorkFollow App tests")
                if selected.isEmpty {
                    let capacity = objc_getClassList(nil, 0)
                    let classes = UnsafeMutablePointer<AnyClass>.allocate(capacity: Int(capacity))
                    defer { classes.deallocate() }
                    let count = objc_getClassList(AutoreleasingUnsafeMutablePointer(classes), capacity)
                    for index in 0..<Int(count) {
                        if let type = classes[index] as? XCTestCase.Type, NSStringFromClass(type).hasPrefix("WorkFollowTests.") {
                            suite.addTest(type.defaultTestSuite)
                        }
                    }
                } else {
                    for name in selected {
                        guard let type = NSClassFromString("WorkFollowTests." + name) as? XCTestCase.Type else {
                            throw AIBackendError.failed("找不到测试类：" + name)
                        }
                        suite.addTest(type.defaultTestSuite)
                    }
                }
                suite.run()
                withExtendedLifetime(owner) {}
                let passed = (suite.testRun?.executionCount ?? 0) > 0 && suite.testRun?.totalFailureCount == 0
                fflush(stdout); fflush(stderr)
                exit(passed ? 0 : 1)
            } catch { fputs("App XCTest 启动失败：\(error.localizedDescription)\n", stderr); exit(1) }
            }
        }
        return true
        #else
        return false
        #endif
    }
}
