import AppKit
import QuartzCore
import SwiftUI

/// Artwork is rendered once per size/appearance. Core Animation moves the
/// resulting layers without a timer or a SwiftUI layout pass for each frame.
struct BackgroundLayerMotion {
    let keyPath: String
    let period: Double
    let value: (Double) -> Any
}

struct BackgroundSprite {
    let image: CGImage
    let size: CGSize
    let position: CGPoint
    var opacity: Float = 1
    var blendFilter: String?
    var motions: [BackgroundLayerMotion] = []
}

@MainActor
enum BackgroundArtworkCache {
    private static let images: NSCache<NSString, CGImage> = {
        let cache = NSCache<NSString, CGImage>()
        cache.totalCostLimit = 64 * 1024 * 1024
        cache.countLimit = 64
        return cache
    }()
    private(set) static var renderCount = 0

    static func image(key: String, size: CGSize, scale: CGFloat,
                      content: AnyView) -> CGImage? {
        let key = "\(key)|\(size.width)|\(size.height)|\(scale)" as NSString
        if let image = images.object(forKey: key) { return image }
        let renderer = ImageRenderer(content: content.frame(width: size.width, height: size.height))
        renderer.scale = scale
        guard let image = renderer.cgImage else { return nil }
        images.setObject(image, forKey: key, cost: image.bytesPerRow * image.height)
        renderCount += 1
        return image
    }
}

struct NativeBackgroundRenderer: NSViewRepresentable {
    let theme: NativeBackgroundTheme
    let dark: Bool
    let animated: Bool
    let backgroundLayer: WorkFollowBackgroundLayer

    func makeNSView(context: Context) -> Backdrop { Backdrop() }

    func updateNSView(_ view: Backdrop, context: Context) {
        view.configure(theme: theme, dark: dark, animated: animated, backgroundLayer: backgroundLayer)
    }

    final class Backdrop: NSView {
        private struct ArtworkKey: Equatable {
            let theme: NativeBackgroundTheme
            let dark: Bool
            let backgroundLayer: WorkFollowBackgroundLayer
            let size: CGSize
            let scale: CGFloat
        }
        private var theme = NativeBackgroundTheme.none
        private var dark = false
        private var animated = false
        private var backgroundLayer = WorkFollowBackgroundLayer.full
        private var artworkKey: ArtworkKey?
        private(set) var sprites: [BackgroundSprite] = []
        private(set) var spriteLayers: [CALayer] = []
        private var playing = false

        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer?.masksToBounds = true
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        func configure(theme: NativeBackgroundTheme, dark: Bool, animated: Bool,
                       backgroundLayer: WorkFollowBackgroundLayer) {
            self.theme = theme; self.dark = dark
            self.animated = animated; self.backgroundLayer = backgroundLayer
            needsLayout = true
            updateAnimation()
        }

        override func layout() {
            super.layout()
            guard bounds.width > 0, bounds.height > 0, let layer else { return }
            let scale = window?.backingScaleFactor ?? 2
            let key = ArtworkKey(theme: theme, dark: dark, backgroundLayer: backgroundLayer,
                                 size: bounds.size, scale: scale)
            guard artworkKey != key else { return }
            artworkKey = key
            sprites = BackgroundArtwork.sprites(theme: theme, dark: dark, size: bounds.size,
                                                 scale: scale, layer: backgroundLayer)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.sublayers = nil
            spriteLayers = sprites.map { sprite in
                let result = CALayer()
                result.contents = sprite.image
                result.contentsScale = scale
                result.bounds = CGRect(origin: .zero, size: sprite.size)
                result.position = sprite.position
                result.opacity = sprite.opacity
                result.compositingFilter = sprite.blendFilter
                layer.addSublayer(result)
                return result
            }
            CATransaction.commit()
            playing = false
            updateAnimation(force: true)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            needsLayout = true
            updateAnimation()
        }

        private func updateAnimation(force: Bool = false) {
            let shouldPlay = animated && window != nil
            guard force || shouldPlay != playing else { return }
            playing = shouldPlay
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for (sprite, layer) in zip(sprites, spriteLayers) {
                layer.removeAllAnimations()
                for motion in sprite.motions {
                    layer.setValue(motion.value(11.6), forKeyPath: motion.keyPath)
                    guard shouldPlay else { continue }
                    let animation = CAKeyframeAnimation(keyPath: motion.keyPath)
                    animation.duration = motion.period
                    animation.repeatCount = .infinity
                    animation.values = (0...64).map { motion.value(11.6 + Double($0) / 64 * motion.period) }
                    animation.calculationMode = .linear
                    layer.add(animation, forKey: motion.keyPath)
                }
            }
            CATransaction.commit()
        }
    }
}
