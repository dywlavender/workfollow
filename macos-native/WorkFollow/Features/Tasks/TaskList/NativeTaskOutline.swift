import AppKit
import SwiftUI

enum TaskOutlineKey { case up, down, enter, space, escape }

/// AppKit owns scrolling and row reuse. The existing projection owns the
/// visible hierarchy, so expansion and task selection still have one owner.
struct NativeTaskOutline: NSViewRepresentable {
    struct Row {
        let id: String
        let makeContent: () -> AnyView
        private var contentState: ComparisonValue?
        private var layoutState: ComparisonValue?

        init<Content: View>(id: String, @ViewBuilder content: @escaping () -> Content) {
            self.id = id
            makeContent = { AnyView(content()) }
        }

        init<State: Equatable, Layout: Equatable, Content: View>(id: String,
            state: State, layout: Layout, @ViewBuilder content: @escaping () -> Content) {
            self.init(id: id, content: content)
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
        let scroll = NSScrollView()
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.contentView.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.wantsLayer = true

        let outline = OutlineView()
        outline.headerView = nil
        outline.cornerView = nil
        outline.style = .plain
        outline.backgroundColor = .clear
        outline.intercellSpacing = .zero
        outline.rowHeight = WFMetrics.rowHeight
        outline.usesAutomaticRowHeights = true
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

    final class Cell: NSTableCellView {
        let host = NSHostingView(rootView: AnyView(EmptyView()))
        var itemID: String?
#if DEBUG
        private(set) var configurationCount = 0
#endif

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            host.translatesAutoresizingMaskIntoConstraints = false
            host.sizingOptions = [.intrinsicContentSize]
            addSubview(host)
            NSLayoutConstraint.activate([
                host.leadingAnchor.constraint(equalTo: leadingAnchor, constant: WFSpace.md),
                host.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -WFSpace.md),
                host.topAnchor.constraint(equalTo: topAnchor),
                host.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        func configure(_ item: Item) {
#if DEBUG
            configurationCount += 1
#endif
            itemID = item.id
            // A reused cell resets SwiftUI state only when it hosts another row.
            host.rootView = AnyView(item.row.makeContent().id(item.id))
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

        func update(_ rows: [Row], in scroll: NSScrollView, scopeKey: String? = nil) {
            guard let outline else { return }
            let scopeChanged = self.scopeKey != scopeKey
            self.scopeKey = scopeKey
            let structureChanged = scopeChanged || items.map(\.id) != rows.map(\.id)
            let visible = outline.rows(in: outline.visibleRect)
            let anchorIndex = visible.location != NSNotFound ? visible.location : 0
            let anchor = items.indices.contains(anchorIndex) ? items[anchorIndex].id : nil
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
                outline.reloadData()
                outline.layoutSubtreeIfNeeded()
                // Insertion/removal above the viewport should not move the
                // task the person is reading out from under the pointer.
                if scopeChanged {
                    scroll.contentView.scroll(to: .zero)
                    scroll.reflectScrolledClipView(scroll.contentView)
                } else if let anchor, let index = items.firstIndex(where: { $0.id == anchor }) {
                    scroll.contentView.scroll(to: NSPoint(x: 0, y: outline.rect(ofRow: index).minY + offset))
                    scroll.reflectScrolledClipView(scroll.contentView)
                }
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
