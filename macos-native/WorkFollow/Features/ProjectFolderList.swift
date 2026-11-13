import SwiftUI

/// `ProjectFolderList` 的非泛型常量。泛型类型装不下 static 存储属性，
/// 而测试也要引用这些值，所以单独放在一个 enum 里。
enum ProjectFolderListMetrics {
    /// 「未归档」伪节点的占位 ID。真实文件夹的 id 由 `UUID()` 随机生成，
    /// 这个固定值不会与它们撞（笔记树的「未归档」同样是固定伪节点 ID）。
    static let unfiledNodeID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    /// 子记录相对节点行缩进的一级。原来只有 12（`WFSpace.md`），比文件夹行
    /// 自身的内边距还浅，子项文字几乎与文件夹文字齐平——层级感就是这么丢的。
    static let childIndent: CGFloat = 24
}

/// 会议纪要 / AI 对话两页共用的「项目文件夹」列表。
///
/// 层级（2026-11-10，用户反馈「文件栏没有层级，看不出属于哪一层级」）照笔记树
/// `NotesFolderTreeListView` 的同款语言重排：
/// - 根级只有节点行——「未归档」伪节点（托盘图标）在前，真实文件夹（文件夹图标）在后；
/// - 记录一律是某个节点的**子项**，缩进一级，不再有「散在根上」的记录；
/// - 节点行右侧带计数胶囊；折叠时子项整组藏起，与笔记树一致。
struct ProjectFolderList<Record: Identifiable, Header: View, Empty: View, Row: View>: View where Record.ID == UUID {
    @Binding var projects: ProjectFolders
    let records: [Record]
    let selectedID: UUID?
    var rowSpacing: CGFloat = 0
    var horizontalInset: CGFloat = 0
    @ViewBuilder let header: (ProjectFolderAddButton) -> Header
    @ViewBuilder let empty: () -> Empty
    @ViewBuilder let row: (Record, ProjectFolderMoveMenu) -> Row

    /// 「未归档」默认展开：新记录都落在未归档，首次进入必须看得见，
    /// 否则等于把现状（散记录常驻）改没。此后随用户折叠，选中时自动展开。
    @State private var expanded: Set<UUID> = [ProjectFolderListMetrics.unfiledNodeID]
    @State private var namePrompt: NamePrompt?
    @State private var folderName = ""
    @State private var nameConflict = false
    @State private var removalTarget: ProjectFolder?

    private enum NamePrompt: Equatable {
        case create, rename(UUID)
    }

    var body: some View {
        let grouped = Dictionary(grouping: records) { projects.folderID(for: $0.id) }
        VStack(alignment: .leading, spacing: 0) {
            header(ProjectFolderAddButton {
                folderName = ""
                namePrompt = .create
            })
            ScrollView {
                LazyVStack(spacing: rowSpacing) {
                    if records.isEmpty && projects.folders.isEmpty {
                        empty()
                    } else {
                        unfiledSection(grouped[nil] ?? [])
                        ForEach(projects.folders) { folder in
                            folderRow(folder, count: grouped[folder.id]?.count ?? 0)
                            if expanded.contains(folder.id) {
                                recordRows(grouped[folder.id] ?? [], folderID: folder.id)
                            }
                        }
                    }
                }
                .padding(.horizontal, horizontalInset)
            }
            .compactScrollbars()
        }
        .onChange(of: selectedID, initial: true) { _, id in
            // 选中项所在的层级自动展开：归档在文件夹里就展开那个文件夹，
            // 散在根上的就展开「未归档」。折叠不该把当前打开的记录藏没。
            if let id { expanded.insert(projects.folderID(for: id) ?? ProjectFolderListMetrics.unfiledNodeID) }
        }
        .workfollowAlert(
            namePrompt == .create ? "新建项目文件夹" : "重命名项目文件夹",
            isPresented: Binding(get: { namePrompt != nil }, set: { if !$0 { namePrompt = nil } }),
            textField: WorkfollowDialogTextField(placeholder: "文件夹名称", text: $folderName),
            actions: [.cancel(), .primary(namePrompt == .create ? "创建" : "保存", action: saveFolderName)])
        .workfollowAlert("文件夹名称已存在", isPresented: $nameConflict, actions: [.primary("好")])
        .workfollowAlert(
            "移除项目文件夹？",
            message: "“\(removalTarget?.name ?? "")”中的记录会回到未归档。",
            isPresented: Binding(get: { removalTarget != nil }, set: { if !$0 { removalTarget = nil } }),
            actions: [.cancel(), .destructive("移除") {
                if let id = removalTarget?.id {
                    projects.remove(id)
                    expanded.remove(id)
                    expanded.insert(ProjectFolderListMetrics.unfiledNodeID)
                }
            }])
    }

    private func toggle(_ id: UUID, isExpanded: Bool) {
        if isExpanded { expanded.remove(id) } else { expanded.insert(id) }
    }

    /// 「未归档」伪节点：托盘图标与真实文件夹区分（笔记树同款）。
    /// 记录即使一条都没有也渲染——它是「移出文件夹」的固定落点，删了就没地方指。
    @ViewBuilder private func unfiledSection(_ records: [Record]) -> some View {
        let isExpanded = expanded.contains(ProjectFolderListMetrics.unfiledNodeID)
        Button { toggle(ProjectFolderListMetrics.unfiledNodeID, isExpanded: isExpanded) } label: {
            HStack(spacing: WFSpace.sm) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold)).frame(width: 10)
                    .foregroundStyle(WFColors.secondaryText)
                Image(systemName: "tray")
                Text(ProjectFolders.unfiledName).lineLimit(1)
                Spacer(minLength: WFSpace.sm)
                countBadge(records.count)
            }
            .font(WFType.supporting)
            .padding(.horizontal, WFSpace.md)
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
            .contentShape(Rectangle())
            .rowHoverBackground(cornerRadius: 6)
        }
        .buttonStyle(.plain)
        .firstMouseAction { toggle(ProjectFolderListMetrics.unfiledNodeID, isExpanded: isExpanded) }
        .accessibilityValue(isExpanded ? "已展开" : "已折叠")
        .accessibilityIdentifier("projects.folder.unfiled")
        .workflowActionAnchor("projects.folder.unfiled")
        if isExpanded {
            recordRows(records, folderID: nil)
        }
    }

    private func folderRow(_ folder: ProjectFolder, count: Int) -> some View {
        let isExpanded = expanded.contains(folder.id)
        return Button { toggle(folder.id, isExpanded: isExpanded) } label: {
            HStack(spacing: WFSpace.sm) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold)).frame(width: 10)
                    .foregroundStyle(WFColors.secondaryText)
                Image(systemName: "folder")
                Text(folder.name).lineLimit(1)
                Spacer(minLength: WFSpace.sm)
                countBadge(count)
            }
            .font(WFType.supporting)
            .padding(.horizontal, WFSpace.md)
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
            .contentShape(Rectangle())
            .rowHoverBackground(cornerRadius: 6)
        }
        .buttonStyle(.plain)
        .firstMouseAction { toggle(folder.id, isExpanded: isExpanded) }
        .accessibilityValue(isExpanded ? "已展开" : "已折叠")
        .accessibilityIdentifier("projects.folder.\(folder.id)")
        .workflowActionAnchor("projects.folder.\(folder.id)")
        .businessContextMenu {
            Button("重命名文件夹…", systemImage: "pencil") {
                folderName = folder.name
                namePrompt = .rename(folder.id)
            }
            Button("移除文件夹…", systemImage: "folder.badge.minus", role: .destructive) {
                removalTarget = folder
            }
        }
    }

    /// 一组子记录。调用时它们一定挂在某个可见节点下（未归档伪节点兜底），
    /// 所以统一缩进一级；`folderID` 仍传 `nil` 表示未归档，供移动菜单标选中态。
    private func recordRows(_ records: [Record], folderID: UUID?) -> some View {
        ForEach(records) { record in
            row(record, ProjectFolderMoveMenu(folders: projects.folders, selectedID: folderID) { destination in
                projects.move(record.id, to: destination)
                if let destination { expanded.insert(destination) }
            })
            .padding(.leading, ProjectFolderListMetrics.childIndent)
        }
    }

    /// 圆角胶囊计数：文件夹与「未归档」统一口径，照笔记树的 `countBadge` 同款。
    private func countBadge(_ count: Int) -> some View {
        Text("\(count)")
            .font(WFType.sidebarBadge)
            .monospacedDigit()
            .foregroundStyle(WFColors.secondaryText)
            .padding(.horizontal, 7)
            .frame(minWidth: 20, minHeight: 16)
            .background(WFColors.quickAddIdleFill, in: Capsule())
    }

    private func saveFolderName() {
        switch namePrompt {
        case .create:
            if let id = projects.create(folderName) { expanded.insert(id) }
            else { nameConflict = true }
        case .rename(let id):
            if !projects.rename(id, to: folderName) { nameConflict = true }
        case nil:
            break
        }
    }
}

struct ProjectFolderAddButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "folder.badge.plus").font(WFType.supporting)
                .frame(width: 28, height: 28).contentShape(Rectangle())
                .rowHoverBackground(cornerRadius: 6)
        }
        .buttonStyle(.plain)
        .foregroundStyle(WFColors.secondaryText)
        .firstMouseAction(action)
        .hoverTip("新建项目文件夹")
        .accessibilityLabel("新建项目文件夹").accessibilityIdentifier("projects.add")
        .workflowActionAnchor("projects.add")
    }
}

struct ProjectFolderMoveMenu: View {
    let folders: [ProjectFolder]
    let selectedID: UUID?
    let move: (UUID?) -> Void

    var body: some View {
        if !folders.isEmpty {
            BusinessMenuSection(title: "移动到文件夹")
            BusinessMenuOption(ProjectFolders.unfiledName, selected: selectedID == nil) { move(nil) }
            ForEach(folders) { folder in
                BusinessMenuOption(folder.name, selected: folder.id == selectedID, symbol: "folder") {
                    move(folder.id)
                }
            }
        }
    }
}
