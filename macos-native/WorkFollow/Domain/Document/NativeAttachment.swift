import Foundation

struct NativeAttachment: Identifiable, Equatable, Codable {
    let id: UUID
    let name: String
    let storedName: String
    /// 用户拖动调整后的显示尺寸（点）。nil 表示按图片原始比例套默认上限。
    ///
    /// 只对以 data URL 内嵌的图片有意义；其他附件忽略该字段。可选字段保证
    /// 旧快照与旧 Quill 文档（没有这两个键）仍能解码，升级不需要迁移。
    var displayWidth: Double? = nil
    var displayHeight: Double? = nil

    init(id: UUID, name: String, storedName: String,
         displayWidth: Double? = nil, displayHeight: Double? = nil) {
        self.id = id
        self.name = name
        self.storedName = storedName
        self.displayWidth = displayWidth
        self.displayHeight = displayHeight
    }

    /// 拖动后写入的新尺寸；两者必须同时有效且为正，否则视为未设置。
    var displaySize: (width: Double, height: Double)? {
        guard let displayWidth, let displayHeight,
              displayWidth.isFinite, displayHeight.isFinite,
              displayWidth >= 1, displayHeight >= 1 else { return nil }
        return (displayWidth, displayHeight)
    }

    /// 是否内嵌可缩放图片（data URL 图片）。
    var isInlineImage: Bool { storedName.hasPrefix("data:image/") }
}
