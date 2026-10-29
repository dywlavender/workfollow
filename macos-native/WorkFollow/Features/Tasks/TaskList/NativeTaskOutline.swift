import AppKit
import SwiftUI

enum TaskOutlineKey { case up, down, enter, space, escape }

/// AppKit owns scrolling and row reuse. The existing projection owns the
/// visible hierarchy, so expansion and task selection still have one owner.
struct NativeTaskOutline: NSViewRepresentable {
#if DEBUG
    @MainActor enum Diagnostics {
        static var containers = 0
        static var createdCells = 0
        static var configurations = 0
        static var configurationTime: Double = 0
        static var updateTime: Double = 0
        static var reloadTime: Double = 0
        static var sizingTime: Double = 0
        static var sizingCalls = 0
        static var rowLayoutTime: Double = 0
        static func reset() {
            containers = 0; createdCells = 0; configurations = 0
            configurationTime = 0; updateTime = 0; reloadTime = 0
            sizingTime = 0; sizingCalls = 0; rowLayoutTime = 0
        }
    }
#endif
    struct Row {
        let id: String
        let makeContent: () -> AnyView
        /// 行高由 `TaskListMetrics.taskRowHeight` 给出（预览行 / 标签行各一档）。
        var height: CGFloat = WFMetrics.rowHeight
        private var contentState: ComparisonValue?
        private var layoutState: ComparisonValue?

        init<Content: View>(id: String, height: CGFloat = WFMetrics.rowHeight,
                            @ViewBuilder content: @escaping () -> Content) {
            self.id = id
            self.height = height
            makeContent = { AnyView(content()) }
        }

        init<State: Equatable, Layout: Equatable, Content: View>(id: String,
            state: State, layout: Layout, height: CGFloat = WFMetrics.rowHeight,
            @ViewBuilder content: @escaping () -> Content) {
            self.init(id: id, height: height, content: content)
            contentState = ComparisonValue(state)
            layoutState = ComparisonValue(layout)
        }

        func hasSameContent(as other: Row) -> Bool { contentState?.matches(other.contentState) == true }
        func hasSameLayout(as other: Row) -> Bool { layoutState?.matches(other.layoutState) == true }

        private struct ComparisonValue {
            let value: Any
            let equals: (Any) -> Bool
            init<Value: Equatable>(_ value: Value) {
                self.value = value
                equals = { ($0 as? Value) == value }
            }
            func matches(_ other: ComparisonValue?) -> Bool {
                guard let other else { return false }
                return equals(other.value)
            }
        }
    }

    let rows: [Row]
    var scopeKey: String? = nil
    var onKey: (TaskOutlineKey) -> Bool = { _ in false }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        Self.makeScrollView(coordinator: context.coordinator)
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.onKey = onKey
        context.coordinator.update(rows, in: scroll, scopeKey: scopeKey)
    }

    static func makeScrollView(coordinator: Coordinator) -> NSScrollView {
#if DEBUG
        Diagnostics.containers += 1
#endif
        let scroll = NSScrollView()
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.contentView.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        CompactScrollStyle.apply(to: scroll)
        // Legacy tiling reserves the 12pt gutter even when content fits;
        // otherwise AppKit widens row cells and the hover background drifts
        // between Today, Tomorrow and other lists. The custom scroller still
        // draws only a slim knob and no track.
        scroll.scrollerStyle = .legacy
        scroll.autohidesScrollers = false
        scroll.wantsLayer = true

        let outline = OutlineView()
        outline.headerView = nil
        outline.cornerView = nil
        outline.style = .plain
        outline.backgroundColor = .clear
        outline.intercellSpacing = .zero
        outline.rowHeight = WFMetrics.rowHeight
        // 行高由 `Row.height`（TaskListMetrics 契约）唯一决定；自动行高会按
        // SwiftUI 固有尺寸测出 48 这类非契约值，还会在标签行更新时测到旧高度。
        outline.usesAutomaticRowHeights = false
        outline.selectionHighlightStyle = .none
        outline.allowsEmptySelection = true
        outline.allowsTypeSelect = false
        outline.indentationPerLevel = 0
        outline.autoresizingMask = [.width]
        outline.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        outline.wantsLayer = true
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("task-content"))
        column.minWidth = 1
        column.width = WFMetrics.listPreferred
        column.resizingMask = .autoresizingMask
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.dataSource = coordinator
        outline.delegate = coordinator
        outline.onKey = { [weak coordinator] key in coordinator?.onKey(key) ?? false }
        coordinator.outline = outline
        scroll.documentView = outline
        return scroll
    }

    final class OutlineView: NSOutlineView {
        var onKey: (TaskOutlineKey) -> Bool = { _ in false }

        override func keyDown(with event: NSEvent) {
            let key: TaskOutlineKey?
            switch event.keyCode {
            case 126: key = .up
            case 125: key = .down
            case 36, 76: key = .enter
            case 49: key = .space
            case 53: key = .escape
            default: key = nil
            }
            if let key, onKey(key) { return }
            nextResponder?.keyDown(with: event)
        }

        // Hierarchy indentation/disclosures are already part of TaskRowView.
        override func frameOfCell(atColumn column: Int, row: Int) -> NSRect {
            var frame = super.frameOfCell(atColumn: column, row: row)
            frame.origin.x = 0
            frame.size.width = bounds.width
            return frame
        }
    }

    final class Item: NSObject {
        let id: String
        var row: Row
        init(_ row: Row) { id = row.id; self.row = row }
    }

#if DEBUG
    final class RowHostingView: NSHostingView<AnyView> {
        override var intrinsicContentSize: NSSize {
            let start = ProcessInfo.processInfo.systemUptime
            defer { Diagnostics.sizingTime += ProcessInfo.processInfo.systemUptime - start }
            Diagnostics.sizingCalls += 1
            return super.intrinsicContentSize
        }
        override func layout() {
            let start = ProcessInfo.processInfo.systemUptime
            defer { Diagnostics.rowLayoutTime += ProcessInfo.processInfo.systemUptime - start }
            super.layout()
        }
    }
#else
    typealias RowHostingView = NSHostingView<AnyView>
#endif

    final class Cell: NSTableCellView {
        let host = RowHostingView(rootView: AnyView(EmptyView()))
        var itemID: String?
#if DEBUG
        private(set) var configurationCount = 0
#endif

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
#if DEBUG
            Diagnostics.createdCells += 1
#endif
            host.translatesAutoresizingMaskIntoConstraints = false
            host.sizingOptions = [.intrinsicContentSize]
            addSubview(host)
            NSLayoutConstraint.activate([
                host.leadingAnchor.constraint(equalTo: leadingAnchor,
                                              constant: TaskListMetrics.outlineLeadingInset),
                host.trailingAnchor.constraint(equalTo: trailingAnchor,
                                               constant: -TaskListMetrics.outlineTrailingInset),
                host.topAnchor.constraint(equalTo: topAnchor),
                host.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        func configure(_ item: Item) {
#if DEBUG
            let started = ProcessInfo.processInfo.systemUptime
            defer { Diagnostics.configurationTime += ProcessInfo.processInfo.systemUptime - started }
            Diagnostics.configurations += 1
            configurationCount += 1
#endif
            itemID = item.id
            // A reused cell resets SwiftUI state only when it hosts another row.
            host.rootView = AnyView(item.row.makeContent().hidesSystemFocusEffect().id(item.id))
        }
    }

    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
        weak var outline: OutlineView?
        private(set) var items: [Item] = []
        var onKey: (TaskOutlineKey) -> Bool = { _ in false }
        private var scopeKey: String?
        private let cellID = NSUserInterfaceItemIdentifier("task-row")
#if DEBUG
        // Test-only ablation: isolate hosting updates from row-height invalidation.
        var refreshContent = true
        var refreshHeights = true
        private(set) var configuredCellCount = 0
        private(set) var heightInvalidationCount = 0
#endif

        @MainActor func update(_ rows: [Row], in scroll: NSScrollView, scopeKey: String? = nil) {
#if DEBUG
            let started = ProcessInfo.processInfo.systemUptime
            defer { Diagnostics.updateTime += ProcessInfo.processInfo.systemUptime - started }
#endif
            guard let outline else { return }
            let scopeChanged = self.scopeKey != scopeKey
            self.scopeKey = scopeKey
            let structureChanged = scopeChanged || items.map(\.id) != rows.map(\.id)
            let previousY = scroll.contentView.bounds.minY
            let visible = outline.rows(in: outline.visibleRect)
            let anchorIndex = visible.location != NSNotFound ? visible.location : 0
            let anchor = previousY > 0 && items.indices.contains(anchorIndex) ? items[anchorIndex].id : nil
            let offset = anchor != nil ? scroll.contentView.bounds.minY - outline.rect(ofRow: anchorIndex).minY : 0
            let oldItems = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
            var contentChanged = IndexSet()
            var layoutChanged = IndexSet()
            items = rows.enumerated().map { index, row in
                let old = oldItems[row.id]
                if old?.row.hasSameContent(as: row) != true { contentChanged.insert(index) }
                if old?.row.hasSameLayout(as: row) != true { layoutChanged.insert(index) }
                let item = old ?? Item(row)
                // Keep the latest builder even when presentation is unchanged.
                item.row = row
                return item
            }

            if structureChanged {
#if DEBUG
                let reloadStart = ProcessInfo.processInfo.systemUptime
#endif
                outline.reloadData()
                outline.layoutSubtreeIfNeeded()
#if DEBUG
                Diagnostics.reloadTime += ProcessInfo.processInfo.systemUptime - reloadStart
#endif
                // Stay at the top while adding to an empty/top-aligned list.
                // Otherwise its bottom spacer can become an anchor and scroll
                // every newly inserted task above the viewport. Preserve a
                // reading anchor only after the person has scrolled down.
                var targetY: CGFloat = 0
                if !scopeChanged, previousY > 0 {
                    if let anchor, let index = items.firstIndex(where: { $0.id == anchor }) {
                        targetY = outline.rect(ofRow: index).minY + offset
                    } else {
                        targetY = previousY
                    }
                }
                let maximumY = max(0, outline.frame.height - scroll.contentView.bounds.height)
                scroll.contentView.scroll(to: NSPoint(x: 0, y: min(max(0, targetY), maximumY)))
                scroll.reflectScrolledClipView(scroll.contentView)
            } else if visible.location != NSNotFound {
                let end = min(NSMaxRange(visible), items.count)
                for index in visible.location..<end where contentChanged.contains(index) || layoutChanged.contains(index) {
#if DEBUG
                    guard refreshContent else { continue }
#endif
                    if let cell = outline.view(atColumn: 0, row: index, makeIfNecessary: false) as? Cell {
                        cell.configure(items[index])
#if DEBUG
                        configuredCellCount += 1
#endif
                    }
                }
            }
            if !structureChanged && !layoutChanged.isEmpty {
#if DEBUG
                guard refreshHeights else { return }
                heightInvalidationCount += layoutChanged.count
#endif
                outline.noteHeightOfRows(withIndexesChanged: layoutChanged)
            }
        }

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            item == nil ? items.count : 0
        }

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            items[index]
        }

        func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
            (item as? Item)?.row.height ?? WFMetrics.rowHeight
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool { false }
        func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool { false }
        func outlineView(_ outlineView: NSOutlineView, shouldShowOutlineCellForItem item: Any) -> Bool { false }

        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let item = item as? Item else { return nil }
            let cell = outlineView.makeView(withIdentifier: cellID, owner: self) as? Cell ?? Cell()
            cell.identifier = cellID
            cell.configure(item)
            return cell
        }
    }
}
