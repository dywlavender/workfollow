// make-app-icon.swift — WorkFollow 应用图标的唯一来源。
//
// 图标不是手绘的位图，而是这个脚本渲染出来的。改图标请改这里再重新生成，
// 不要直接编辑 .appiconset 里的 PNG（那些是产物）。
//
// 生成（在 macos-native/ 下）：
//   swiftc -O -parse-as-library scripts/make-app-icon.swift -o /tmp/mkicon
//   /tmp/mkicon iconset WorkFollow/Resources/Assets.xcassets/AppIcon.appiconset
//
// 只想看单个尺寸：
//   /tmp/mkicon one 512 /tmp/preview.png
//
// ── 设计：浅色纸面底 + 靛蓝对勾 + 琥珀清单条 ──────────────────────
//
// 参照物是滴答清单的 macOS 版图标。把它自己的 AppIcon.icns 拆开量过：
// 它是【浅色纸面底 + 蓝色圆环 + 琥珀色勾】，靠两种颜色的笔画立身份，
// 而不是「彩色方砖 + 白勾」（那是它的手机版/网页版）。
// 我们 app 的界面本身也是浅色 + 靛蓝强调色，所以浅底才是一致的。
//
// 记号本身仍是产品自己的：对勾取自 Web 端 favicon
// （workfollow-flutter-personal/frontend/public/favicon.svg）的
// `M17.5 33.5 L27.5 43.5 L46.5 21.5`，stroke 7，在 64pt 框里。
// 琥珀色取自设计 token 里的暖色档（WFColors.warning 那一族）。
//
// 勾的靛蓝取 #7B80F4，而不是更深的 #4F51E5 / app accent #5B5CEB——
// 用户反馈「太深了」。这个值落在 favicon 渐变（#818CF8 → #4F46E5）的**浅端**，
// 仍在品牌色域内；对白底对比度 3.4:1，16pt 下勾形仍立得住。
// 再淡一档（#8B90F8）16pt 就开始发虚了。
//
// ⚠️ 对勾必须**按墨迹包围盒居中**，不是按三个控制点居中——两者中心不一样。
//    而且画进方砖的路径要用「方砖本地坐标 0..824」，最后再整体居中到 1024 画布。
//    之前有一版把已含 100pt 边距的画布坐标直接画进方砖，于是又叠了一次偏移，
//    对勾整体偏右下 100px（占方砖 12%），肉眼一看就是「没放正」。
//
// ── 几何：Apple 的 macOS 图标网格 ──────────────────────────────
// 1024pt 画布，圆角方砖 824×824 居中（四边各留 100pt），
// 圆角半径 185.4，且必须用 `.continuous`（squircle），不能用正圆弧。
//
// ── 三个试出来的配比 ──────────────────────────────────────────
// 1. 勾的墨迹宽 = 方砖的 46%、笔画 = 78（方砖单位）。再大就糊满方砖、再小则 16pt 下没形。
// 2. 琥珀条宽 = 方砖的 40%、高 54、两端全圆角。比这细会读成一根孤零零的「减号」。
// 3. 勾与条的间距 = 46（方砖单位）。整组（勾 + 间距 + 条）一起在方砖里垂直居中，
//    而不是各自居中——否则整组会偏上。

import SwiftUI
import AppKit

private let FAVICON_CHECK: [(CGFloat, CGFloat)] = [(17.5, 33.5), (27.5, 43.5), (46.5, 21.5)]
private let FAVICON_BOX: CGFloat = 64

private let indigo = Color(red: 0.482, green: 0.502, blue: 0.957)   // #7B80F4
private let amber  = Color(red: 0.949, green: 0.655, blue: 0.196)   // #F2A732

/// 把 favicon 的勾换算成方砖本地坐标下的路径。
/// `markWidth` 是**墨迹**宽度（含笔画），`stroke` 是笔画宽，`centerY` 是墨迹中心的目标 y。
private func checkPath(tile: CGFloat, markWidth: CGFloat, stroke: CGFloat,
                       centerY: CGFloat) -> Path {
    let k = tile / FAVICON_BOX
    let pts = FAVICON_CHECK.map { CGPoint(x: $0.0 * k, y: $0.1 * k) }
    let s = (markWidth - stroke) / (pts[2].x - pts[0].x)   // 让「跨度 + 笔画」正好等于目标墨迹宽
    let inkCX = (pts[0].x + pts[2].x) / 2
    let inkCY = (pts[1].y + pts[2].y) / 2
    var p = Path()
    for (i, pt) in pts.enumerated() {
        let x = (pt.x - inkCX) * s + tile / 2
        let y = (pt.y - inkCY) * s + centerY
        i == 0 ? p.move(to: CGPoint(x: x, y: y)) : p.addLine(to: CGPoint(x: x, y: y))
    }
    return p
}

/// 勾的墨迹高，用来把「勾 + 间距 + 条」整组垂直居中。
private func checkInkHeight(tile: CGFloat, markWidth: CGFloat, stroke: CGFloat) -> CGFloat {
    let k = tile / FAVICON_BOX
    let pts = FAVICON_CHECK.map { CGPoint(x: $0.0 * k, y: $0.1 * k) }
    let s = (markWidth - stroke) / (pts[2].x - pts[0].x)
    return (pts[1].y - pts[2].y) * s + stroke
}

private struct IconArt: View {
    let size: CGFloat

    private var s: CGFloat { size / 1024 }      // 1024pt 设计空间 → 目标像素
    private var tile: CGFloat { 824 * s }
    private var radius: CGFloat { 185.4 * s }
    private var u: CGFloat { tile / 824 }       // 方砖单位（= s）

    // 三个配比，见文件头
    private var markWidth: CGFloat { 0.46 * tile }
    private var stroke: CGFloat { 78 * u }
    private var barW: CGFloat { 0.40 * tile }
    private var barH: CGFloat { 54 * u }
    private var gap: CGFloat { 46 * u }

    private var checkH: CGFloat {
        checkInkHeight(tile: tile, markWidth: markWidth, stroke: stroke)
    }
    private var groupTop: CGFloat { (tile - (checkH + gap + barH)) / 2 }
    private var checkCenterY: CGFloat { groupTop + checkH / 2 }
    private var barCenterY: CGFloat { groupTop + checkH + gap + barH / 2 }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack {
            // 纸面底：近白微渐变。纯白在浅色背景上会消失，所以再加一圈极淡描边。
            shape.fill(LinearGradient(colors: [Color(white: 1.0), Color(white: 0.929)],
                                      startPoint: .top, endPoint: .bottom))
            shape.strokeBorder(Color.black.opacity(0.07), lineWidth: max(1, 2 * u))
            // 顶部棱光：macOS 图标「从上方受光」的签名
            shape.strokeBorder(LinearGradient(colors: [.white, .white.opacity(0)],
                                              startPoint: .top, endPoint: .center),
                               lineWidth: max(1, 3 * u))

            checkPath(tile: tile, markWidth: markWidth, stroke: stroke, centerY: checkCenterY)
                .stroke(indigo, style: StrokeStyle(lineWidth: stroke,
                                                   lineCap: .round, lineJoin: .round))

            RoundedRectangle(cornerRadius: barH / 2, style: .continuous)
                .fill(amber)
                .frame(width: barW, height: barH)
                .position(x: tile / 2, y: barCenterY)
        }
        .frame(width: tile, height: tile)
        .frame(width: size, height: size)   // 方砖居中到整块画布
        .shadow(color: .black.opacity(0.16), radius: 20 * s, x: 0, y: 11 * s)
    }
}

/// macOS `.appiconset` 要求的十个条目：文件名 → 像素边长。
/// 同一像素边长会出现两次（如 128@2x 与 256@1x 都是 256px），
/// 这里各渲染一次，不共用文件——重复是规范的一部分。
let iconSetEntries: [(name: String, size: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

let iconSetContentsJSON = """
{
  "images" : [
    { "filename" : "icon_16x16.png",      "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "filename" : "icon_16x16@2x.png",   "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "filename" : "icon_32x32.png",      "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
    { "filename" : "icon_32x32@2x.png",   "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
    { "filename" : "icon_128x128.png",    "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "filename" : "icon_128x128@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "filename" : "icon_256x256.png",    "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "filename" : "icon_256x256@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "filename" : "icon_512x512.png",    "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "filename" : "icon_512x512@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
""" + "\n"

@main
struct MakeAppIcon {
    @MainActor
    static func main() throws {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let mode = args.first else { usage() }

        switch mode {
        case "one":
            guard args.count >= 3, let px = Double(args[1]) else { usage() }
            try render(pixels: CGFloat(px), to: URL(fileURLWithPath: args[2]))

        case "iconset":
            guard args.count >= 2 else { usage() }
            let dir = URL(fileURLWithPath: args[1], isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for entry in iconSetEntries {
                try render(pixels: CGFloat(entry.size),
                           to: dir.appendingPathComponent(entry.name))
            }
            try iconSetContentsJSON.write(to: dir.appendingPathComponent("Contents.json"),
                                          atomically: true, encoding: .utf8)
            print("wrote \(iconSetEntries.count) png + Contents.json to \(dir.path)")

        default:
            usage()
        }
    }

    /// 逐尺寸重新矢量渲染（不是缩放），这样小尺寸的边缘才干净。
    @MainActor
    private static func render(pixels: CGFloat, to url: URL) throws {
        let renderer = ImageRenderer(content: IconArt(size: pixels))
        renderer.scale = 1
        renderer.isOpaque = false
        guard let cg = renderer.cgImage else {
            FileHandle.standardError.write("render failed at \(pixels)px\n".data(using: .utf8)!)
            exit(1)
        }
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
        try data.write(to: url)
    }

    private static func usage() -> Never {
        FileHandle.standardError.write("""
        usage:
          make-app-icon one <pixels> <out.png>
          make-app-icon iconset <AppIcon.appiconset 目录>

        """.data(using: .utf8)!)
        exit(2)
    }
}
