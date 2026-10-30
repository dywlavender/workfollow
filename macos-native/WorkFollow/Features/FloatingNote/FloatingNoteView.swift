import AppKit
import SwiftUI

/// Note adapter: persistence and note actions stay in the note module.
struct FloatingNoteView: View {
    let noteID: UUID
    @ObservedObject var notes: NotesWorkspaceModel
    let tasks: TaskWorkspaceModel
    let editorHandle: DocumentEditorHandle
    let focusAtEnd: Bool
    let onClose: () -> Void

    @EnvironmentObject private var environment: AppEnvironment
    @AppStorage("notes.ai.paneWidth") private var aiPaneWidth = Double(NoteAIPaneMetrics.defaultWidth)
    @StateObject private var aiExpansion = AIPaneWindowExpansion()
    @State private var aiOpen = false
    @State private var aiDestination = TaskList.inbox.name
    @State private var aiSectionID: String?
    @State private var aiDraftEdit: NoteAIDraftEditTarget?

    private var note: Note? {
        notes.notes.first { $0.id == noteID && $0.deletedAt == nil }
    }

    var body: some View {
        if let note {
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    editor(note)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if aiOpen, aiExpansion.isExpanded {
                        Rectangle().fill(WFColors.border).frame(width: WFMetrics.divider)
                        aiPane(note: note).frame(width: aiExpansion.expandedWidth)
                    }
                }
                .overlay(alignment: .trailing) {
                    if aiOpen, !aiExpansion.isExpanded {
                        aiPane(note: note)
                            .frame(width: min(CGFloat(aiPaneWidth),
                                              max(240, geometry.size.width - 340)))
                            .background(WFColors.panelFill)
                            .shadow(color: .black.opacity(0.18), radius: 18, x: -6, y: 0)
                    }
                }
                .overlay { aiDraftOverlay(note: note) }
                .coordinateSpace(name: PlanningCoordinateSpace.name)
                // 编辑区忽略标题栏安全区（FloatingEditorView 内），AI 栏也要落到同一原点，
                // 两栏顶部分割线才能对齐。
                .ignoresSafeArea(.container, edges: .top)
            }
            .onAppear { panel?.onWillClose = { aiExpansion.collapse() } }
            .onDisappear {
                panel?.onWillClose = nil
                aiExpansion.collapse()
            }
        }
    }

    private func editor(_ note: Note) -> some View {
        FloatingEditorView(documentID: noteID,
            title: Binding(get: { notes.notes.first(where: { $0.id == noteID })?.title ?? "" },
                           set: { value in notes.edit(noteID) { $0.title = value } }),
            titlePlaceholder: "未命名笔记",
            titleAccessibilityLabel: "笔记标题",
            document: note.document,
            onDocumentChange: { document in notes.edit(noteID) { $0.document = document } },
            profile: NoteDocumentProfile.make(host: NoteEditorHostActions.make(
                noteID: noteID, tasks: tasks, notes: notes)),
            editorHandle: editorHandle, focusAtEnd: focusAtEnd,
            onClose: closePanel, actions: EmptyView(),
            topBar: { topBar(note) })
    }

    private func topBar(_ note: Note) -> some View {
        HStack {
            Text(NoteDateLabel.tickStyle(note.updatedAt))
                .font(WFType.body.weight(.medium))
                .foregroundStyle(WFColors.accent)
            Spacer(minLength: 8)
            Button(action: toggleAI) {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                    Text("AI")
                }
                .font(WFType.supporting)
                .foregroundStyle(aiOpen ? WFColors.accent : WFColors.secondaryText)
                .padding(.horizontal, 7)
                .frame(height: 24)
                .background(aiOpen ? WFColors.selection : Color.clear,
                            in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(aiOpen ? "关闭 AI 助手" : "打开 AI 助手")
            .hoverTip(aiOpen ? "关闭 AI 助手" : "AI 助手")
            .accessibilityIdentifier("floating.note.ai")
        }
        .padding(.horizontal, FloatingEditorMetrics.contentHorizontalPadding)
        .frame(height: FloatingEditorMetrics.topBarHeight)
    }

    private var panel: FloatingEditorPanel? {
        FloatingEditorWindowController.shared.panel(for: .note(noteID))
    }

    private func toggleAI() {
        if aiOpen {
            closeAI()
        } else {
            if let panel { _ = aiExpansion.expand(panel, by: CGFloat(aiPaneWidth)) }
            aiOpen = true
        }
    }

    private func closeAI() {
        aiOpen = false
        aiDraftEdit = nil
        aiExpansion.collapse()
    }

    private func closePanel() {
        aiExpansion.collapse()
        onClose()
    }

    private func aiPane(note: Note) -> some View {
        NoteAIPaneView(model: NoteAIConversationStore.shared.model(for: note.id), tasks: tasks,
                       noteID: note.id,
                       noteTitle: note.title.isEmpty ? "未命名笔记" : note.title,
                       noteContentIsEmpty: note.document.plainText
                           .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       canReplaceBody: !note.hasPreservedRichContent,
                       destination: $aiDestination, sectionID: $aiSectionID,
                       makeContext: { noteAIContext(noteID: note.id) },
                       onPrepareDocument: { editorHandle.prepareForDocumentChange() },
                       onReplaceBody: { replaceNoteBody($0, noteID: note.id) },
                       onEditDraft: { exchangeID, draftID, rect in
                           let anchor = PlanningAnchorRef()
                           anchor.rect = rect
                           aiDraftEdit = NoteAIDraftEditTarget(exchangeID: exchangeID,
                                                               draftID: draftID, anchor: anchor)
                       },
                       onRevealTasks: revealTasks,
                       onOpenNote: openNote,
                       onClose: closeAI)
    }

    @ViewBuilder
    private func aiDraftOverlay(note: Note) -> some View {
        if let target = aiDraftEdit,
           let exchange = NoteAIConversationStore.shared.model(for: note.id)
               .exchange(id: target.exchangeID),
           let session = exchange.taskSession,
           let request = exchange.taskRequest {
            PlanningOverlayLayer(anchor: target.anchor,
                                 placement: WFOverlayPlacement(preferredSide: .left, alignment: .center),
                                 size: NoteAIPaneMetrics.draftEditorSize,
                                 onDismiss: { aiDraftEdit = nil }) {
                NoteAITaskDraftEditorHost(session: session, draftID: target.draftID,
                                          request: request, destination: aiDestination,
                                          tasks: tasks, onClose: { aiDraftEdit = nil })
                    .environmentObject(environment)
            }
        }
    }

    private func noteAIContext(noteID: UUID) -> NoteAIContext {
        guard let note = notes.notes.first(where: { $0.id == noteID && $0.deletedAt == nil }) else {
            return NoteAIContext(noteID: noteID, title: "", content: "",
                                 referenceDate: Date(), existingTitles: [])
        }
        return NoteAIContext(noteID: note.id,
                             title: note.title.isEmpty ? "未命名笔记" : note.title,
                             content: note.document.plainText,
                             referenceDate: note.updatedAt,
                             existingTitles: tasks.allTasks.filter {
                                 $0.deletedAt == nil
                                     && ($0.sourceNoteID == note.id || note.linkedTaskIDs.contains($0.id))
                             }.map(\.title))
    }

    private func replaceNoteBody(_ text: String, noteID: UUID) {
        guard notes.notes.contains(where: { $0.id == noteID && $0.deletedAt == nil }) else { return }
        editorHandle.prepareForDocumentChange()
        let body = DocumentExternalClipboardCodec.fragment(fromMarkdown: text)?.document
            ?? NativeDocument(plainText: text)
        notes.edit(noteID) { $0.document = body }
    }

    private func revealTasks(_ ids: [UUID]) {
        guard let id = ids.first else { return }
        _ = NativeResourceLinkRouter.open(.task(id), tasks: tasks, notes: notes,
                                          navigation: environment.navigation)
    }

    private func openNote(_ id: UUID) {
        _ = NativeResourceLinkRouter.open(.note(id), tasks: tasks, notes: notes,
                                          navigation: environment.navigation)
    }
}
