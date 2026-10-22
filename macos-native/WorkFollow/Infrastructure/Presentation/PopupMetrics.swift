import CoreGraphics
import Foundation

/// Shared presentation values. Content-specific widths remain named by purpose.
enum PopupMetrics {
    static let cornerRadius: CGFloat = 12
    static let screenInset: CGFloat = 8
    static let controlGap: CGFloat = 4
    static let scheduleGap: CGFloat = 6
    static let submenuGap: CGFloat = 6
    static let contentInset: CGFloat = 12
    static let actionSpacing: CGFloat = 12
    static let compactButtonHeight: CGFloat = 26
    static let buttonCornerRadius: CGFloat = 6
    static let formInset: CGFloat = 24
    static let formFooterInset: CGFloat = 16
    static let submenuIntent: TimeInterval = 0.22
    static let menuWidth: CGFloat = 224
    static let menuRowHeight: CGFloat = 32
    static let menuInset: CGFloat = 6
    static let menuMaximumHeight: CGFloat = 384

    static let taskMenuWidth: CGFloat = 176
    static let taskActionsWidth: CGFloat = 208
    static let noteInfoWidth: CGFloat = 220
    static let tagPickerWidth: CGFloat = 264
    static let parentPickerWidth: CGFloat = 280
    static let focusEstimateWidth: CGFloat = 280
    static let relationPickerWidth: CGFloat = 320
    static let quickAddPropertiesWidth: CGFloat = 270
    static let syncStatusWidth: CGFloat = 340
}
