import SwiftUI

/// 引导演示录制的几何锚：SwiftUI 的侧栏按钮不进 AX 树，录制器改为读取
/// 生产布局自己报出的 frame（坐标空间由录制夹具定义）。
/// 生产构建里没有观察者，修饰符是空实现。
struct GuideTourFramesKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

#if DEBUG
extension Notification.Name {
    static let guideTourCopySummary = Notification.Name("WorkFollow.guideTour.copySummary")
}
#endif

extension View {
    @ViewBuilder
    func guideTourAnchor(_ id: String) -> some View {
        #if DEBUG
        background(GeometryReader { geometry in
            Color.clear.preference(
                key: GuideTourFramesKey.self,
                value: [id: geometry.frame(in: .named("guide-tour-render"))]
            )
        })
        #else
        self
        #endif
    }
}
