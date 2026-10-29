import SwiftUI

extension View {
    /// 自绘界面统一不画系统焦点环。
    ///
    /// 开启「全键盘控制」后，弹框打开会把焦点交给首个按钮，点击按钮/开关也会
    /// 移动键盘焦点；系统随即在它们外围补一圈蓝色描边，看起来像被选中。
    /// 修饰符挂在窗口或面板根容器上可覆盖其全部子控件与 sheet，键盘焦点本身保留。
    func hidesSystemFocusEffect() -> some View {
        focusEffectDisabled()
    }
}
