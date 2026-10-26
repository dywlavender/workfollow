import Foundation

/// The inspector's outline and collapsed-count hint describe the same tree.
/// The current task is the root container; only its descendants occupy rows.
struct SubtaskOutlineLayout: Equatable {
    let visibleRowCount: Int
    let hiddenRowCount: Int

    var totalRowCount: Int { visibleRowCount + hiddenRowCount }

    /// Configure the native outline with zero intercell spacing, then supply
    /// the shared inspector row height. The add-child row is separate.
    func height(rowHeight: CGFloat) -> CGFloat {
        CGFloat(visibleRowCount) * rowHeight
    }

    /// `children` must use the same visibility rules as the outline data source.
    /// Hidden descendants are still counted once, even when they are folded too.
    static func measure<ID: Hashable>(under rootID: ID,
                                      children: (ID) -> [ID],
                                      collapsed: Set<ID>) -> Self {
        var visibleRows = 0
        var hiddenRows = 0

        func visitChildren(of parentID: ID, visible: Bool) {
            for childID in children(parentID) {
                if visible { visibleRows += 1 }
                else { hiddenRows += 1 }
                visitChildren(of: childID, visible: visible && !collapsed.contains(childID))
            }
        }

        visitChildren(of: rootID, visible: true)
        return Self(visibleRowCount: visibleRows, hiddenRowCount: hiddenRows)
    }
}
