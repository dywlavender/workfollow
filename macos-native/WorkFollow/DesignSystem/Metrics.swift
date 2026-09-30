import Foundation

enum RailMetrics {
    static let width: CGFloat = 52
    static let iconSize: CGFloat = 18
    static let hitSize: CGFloat = 34
    static let selectedSize: CGFloat = 30
    static let selectedRadius: CGFloat = 9
    static let itemGap: CGFloat = 12
    static let topPadding: CGFloat = 16
}

enum WFMetrics {
    static let minimumWindow = CGSize(width: 360, height: 480)
    static let defaultWindow = CGSize(width: 1280, height: 820)
    static let railWidth: CGFloat = RailMetrics.width
    static let navigationWidth: CGFloat = 196
    static let listMinimum: CGFloat = 380
    static let listPreferred: CGFloat = 440
    static let listMaximum: CGFloat = 470
    static let inspectorMinimum: CGFloat = 320
    static let divider: CGFloat = 1
    static let splitMinimum = listMinimum + inspectorMinimum + divider
    static let navigationBreakpoint = railWidth + navigationWidth + splitMinimum + 2 * divider
    static let rowHeight: CGFloat = 50
    static let rowVerticalPadding: CGFloat = 11
    static var rowContentMinHeight: CGFloat { rowHeight - rowVerticalPadding * 2 }
    static let controlHeight: CGFloat = 34
    static let corner: CGFloat = 8
    static let icon: CGFloat = 18
    static let secondaryMetadataLimit = 3
}
