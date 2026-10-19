import SwiftUI

struct TaskKanbanColumnLayout: Equatable {
    var cards: [UUID: CGRect] = [:]
    var rows: [UUID: CGRect] = [:]
    var viewport: CGRect = .zero
}

struct TaskKanbanColumnLayoutKey: PreferenceKey {
    static let defaultValue = TaskKanbanColumnLayout()

    static func reduce(value: inout TaskKanbanColumnLayout,
                       nextValue: () -> TaskKanbanColumnLayout) {
        let next = nextValue()
        value.cards.merge(next.cards, uniquingKeysWith: { _, new in new })
        value.rows.merge(next.rows, uniquingKeysWith: { _, new in new })
        if !next.viewport.isEmpty { value.viewport = next.viewport }
    }
}

enum TaskKanbanFrame {
    case card(UUID), row(UUID), viewport
}

extension View {
    func kanbanDropFrame(_ part: TaskKanbanFrame) -> some View {
        background {
            GeometryReader { geometry in
                let frame = geometry.frame(in: .named("kanban-column"))
                Color.clear.preference(key: TaskKanbanColumnLayoutKey.self, value: {
                    switch part {
                    case .card(let id): TaskKanbanColumnLayout(cards: [id: frame])
                    case .row(let id): TaskKanbanColumnLayout(rows: [id: frame])
                    case .viewport: TaskKanbanColumnLayout(viewport: frame)
                    }
                }())
            }
        }
    }
}

/// Insertion belongs to a gap between sibling cards; hovering the body of a
/// card never implicitly changes parent membership.
struct TaskKanbanInsertion: Equatable {
    let placement: TaskDropPlacement?
    let y: CGFloat

    static func resolve(at y: CGFloat, orderedIDs: [UUID], frames: [UUID: CGRect],
                        viewport: CGRect) -> Self {
        let cards = orderedIDs.compactMap { id -> (UUID, CGRect)? in
            guard let frame = frames[id], !frame.isEmpty else { return nil }
            return (id, frame)
        }.sorted { $0.1.minY < $1.1.minY }
        let placement: TaskDropPlacement?
        let lineY: CGFloat
        if let next = cards.first(where: { y < $0.1.midY }) {
            placement = .before(next.0)
            lineY = next.1.minY - WFSpace.xs / 2
        } else if let last = cards.last {
            placement = .after(last.0)
            lineY = last.1.maxY + WFSpace.xs / 2
        } else {
            placement = nil
            lineY = viewport.minY + WFSpace.xs
        }
        let clamped = viewport.isEmpty ? lineY
            : min(max(lineY, viewport.minY + 1), viewport.maxY - 1)
        return Self(placement: placement, y: clamped)
    }
}
