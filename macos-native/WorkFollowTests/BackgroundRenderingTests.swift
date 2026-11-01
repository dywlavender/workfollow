import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class BackgroundRenderingTests: XCTestCase {
    func testArtworkAndLayersAreReusedWhileAnimationCanPause() throws {
        for theme in NativeBackgroundTheme.allCases where theme.isThemed {
            let view = NativeBackgroundRenderer.Backdrop(frame: NSRect(x: 0, y: 0, width: 960, height: 640))
            let window = InspectorPanelTestSupport.ownerWindow(for: view, width: 960, height: 640)
            defer { window.close(); window.contentView = nil }
            view.configure(theme: theme, dark: false, animated: true, backgroundLayer: .full)
            view.layoutSubtreeIfNeeded()
            XCTAssertFalse(view.sprites.isEmpty)
            let layers = view.spriteLayers
            XCTAssertTrue(layers.contains { !($0.animationKeys() ?? []).isEmpty })
            let renders = BackgroundArtworkCache.renderCount
            RunLoop.main.run(until: Date().addingTimeInterval(0.15))
            view.configure(theme: theme, dark: false, animated: true, backgroundLayer: .full)
            view.layoutSubtreeIfNeeded()
            XCTAssertEqual(BackgroundArtworkCache.renderCount, renders)
            XCTAssertTrue(zip(layers, view.spriteLayers).allSatisfy { $0 === $1 })
            view.configure(theme: theme, dark: false, animated: false, backgroundLayer: .full)
            view.layoutSubtreeIfNeeded()
            XCTAssertTrue(view.spriteLayers.allSatisfy { ($0.animationKeys() ?? []).isEmpty })
            XCTAssertEqual(BackgroundArtworkCache.renderCount, renders)
            let output = URL(fileURLWithPath: "/private/tmp/workfollow-theme-render-20261101", isDirectory: true)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                .write(to: output.appendingPathComponent(theme.rawValue + ".png"))
            view.configure(theme: theme, dark: true, animated: false, backgroundLayer: .full)
            view.layoutSubtreeIfNeeded()
            XCTAssertFalse(view.sprites.isEmpty)
        }
    }
}
