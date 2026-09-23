import Foundation

enum WFMetrics {
    static let minimumWindow = CGSize(width: 360, height: 480)
    static let defaultWindow = CGSize(width: 1280, height: 820)
    static let railWidth: CGFloat = 52
    static let navigationWidth: CGFloat = 196
    static let listMinimum: CGFloat = 340
    static let listPreferred: CGFloat = 440
    static let listMaximum: CGFloat = 470
    static let inspectorMinimum: CGFloat = 300
    static let divider: CGFloat = 1
    static let splitMinimum = listMinimum + inspectorMinimum + divider
    static let navigationBreakpoint = railWidth + navigationWidth + splitMinimum + 2 * divider
    static let rowHeight: CGFloat = 50
    static let controlHeight: CGFloat = 34
    static let corner: CGFloat = 8
    static let icon: CGFloat = 18
}
