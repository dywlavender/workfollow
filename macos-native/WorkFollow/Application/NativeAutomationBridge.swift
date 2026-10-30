import AppKit

@MainActor
final class NativeAutomationBridge {
    private let channel: AutomationChannel
    private let service: NativeAutomationService
    private let canProcess: () -> Bool
    private let flush: (@escaping (Error?) -> Void) -> Void
    private let onSuccess: ((AutomationRequest, AutomationValue) -> Void)?
    private var observer: NSObjectProtocol?
    private var processing = false

    init(channel: AutomationChannel, service: NativeAutomationService, canProcess: @escaping () -> Bool,
         flush: @escaping (@escaping (Error?) -> Void) -> Void,
         onSuccess: ((AutomationRequest, AutomationValue) -> Void)? = nil) {
        self.channel = channel; self.service = service; self.canProcess = canProcess; self.flush = flush
        self.onSuccess = onSuccess
        observer = DistributedNotificationCenter.default().addObserver(forName: AutomationChannel.notification,
            object: channel.directory.path, queue: .main) { [weak self] _ in
                _Concurrency.Task { @MainActor in await self?.processPending() }
            }
        _Concurrency.Task { @MainActor [weak self] in await self?.processPending() }
    }
    deinit { if let observer { DistributedNotificationCenter.default().removeObserver(observer) } }
    func processPending() async {
        guard !processing else { return }
        processing = true
        defer { processing = false }
        do {
            while true {
                let requests = try channel.pending()
                if requests.isEmpty { return }
                for request in requests {
                    if let response = try channel.response(for: request.id) { try channel.respond(response); continue }
                    let response: AutomationResponse
                    do {
                        guard request.expiresAt >= Date() else { throw AutomationFailure(code: "expired", message: "命令已超时，未执行。") }
                        guard canProcess() else { throw AutomationFailure(code: "storage_unavailable", message: "App 存储尚未就绪，请在应用中处理保存或加载错误后重试。") }
                        let data = try service.execute(request)
                        if NativeAutomationService.writes(request.operation) {
                            let failure: Error? = await withCheckedContinuation { continuation in flush { continuation.resume(returning: $0) } }
                            if let failure { throw AutomationFailure(code: "save_failed", message: "保存失败：" + failure.localizedDescription) }
                        }
                        response = .success(request, data)
                        onSuccess?(request, data)
                    } catch {
                        response = .failure(request, error as? AutomationFailure
                            ?? AutomationFailure(code: "operation_failed", message: error.localizedDescription))
                    }
                    try channel.respond(response)
                }
            }
        } catch {
            // Leave unacknowledged requests for the next notification or launch.
        }
    }
}
