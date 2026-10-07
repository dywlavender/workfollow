import AppKit
import SwiftUI

/// 会议纪要工作区：左栏会议列表 + 右栏详情。
///
/// **结构照 `NotesWorkspaceView` 抄**——两者是同一类页面（一列 + 一详情 + 中间一条线），
/// 所以列宽、行几何、分割线、选中底色、工具行高度全部与任务列/笔记列同口径。
///
/// 详情栏内部再分两栏（2026-10-06，用户选定）：**左「对话记录」右「滚动纪要」**，
/// 各带自己的滚动条与底部操作行。原来这两样是 segmented tab 二选一，但它们是
/// **摘要 ↔ 依据**的关系（`MeetingStore` 里 Pi 就是拿「新增且未被总结」的转写行去
/// 更新纪要的），核对时要对着看，tab 强制你来回切。数据里的 `summarizedLineIDs`
/// 还让「哪些行还没进纪要」本来就可识别——分栏之后这条信息才用得上。
///
/// 右栏的纪要是**可编辑的**（同日稍后，用户要求）：不再有「更新纪要」按钮，
/// 直接改就行。第一笔输入会把这条会议标成「手动」，Pi 随即停止覆盖它
/// （见 `MeetingStore.editMinutes`）；底栏留一条「交回自动更新」的退路。
///
/// 这一页在 `RootShellView` 里是 **rail-only 目的地**（和日历 / 四象限 / 倒数一样，
/// 不挂导航栏），所以它自带列表列是合理的；不合理的只是那一列的实现方式。
struct MeetingWorkspaceView: View {
    @ObservedObject var store: MeetingStore

    @State private var settingsPresented = false
    /// 窄窗口下只显示一栏时的「当前在哪一栏」。宽窗口下恒为 false（两栏都在）。
    @State private var detailOnly = false
    @State private var hoveredMeetingID: UUID?

    // 列表列与详情栏之间那条线
    @State private var listDragOrigin: CGFloat?
    @State private var paneWidth = WFMetrics.listPreferred

    // 详情栏内部那条线：横向时是左栏宽度占比，纵向时是上栏高度占比
    @State private var splitDragOrigin: CGFloat?
    /// 用户自己拖出来的转写栏占比。`nil` = 还没拖过，按相位取默认值。
    /// **不落盘、不加字段**——所以回看时天然回到「对半」。
    @State private var userTranscriptFraction: CGFloat?
    @State private var minutesFraction: CGFloat = 0.45

    // 对话记录的自动跟随。**贴底才跟随**：用内容底边与视口底边的距离判断，
    // 用户上翻回看历史时不能拽人，滚回底部后恢复跟随（聊天 App 的标准做法）。
    @State private var transcriptPinned = true
    @State private var transcriptContentBottom: CGFloat = 0
    @State private var transcriptViewportHeight: CGFloat = 0

    private static let transcriptSpace = "meeting-transcript-scroll"
    private static let bottomAnchorID = "meeting-transcript-bottom"
    /// 贴底判定余量：一行转写的高度以内都算「还在底部」。
    private static let autoFollowThreshold: CGFloat = 60

    /// 转写栏实际占比：**录制中把大栏让给转写**（用户原话：「过程中是转写重要，
    /// 右边显示纪要」），其余时候（暂停 / 回看）回到对半。
    ///
    /// 「相位」是**算出来的，不是存下来的**——只由 `recordingID` 决定，所以不用给
    /// `MeetingRecord` 加字段（用户明确不要），也不必手动切。代价是按下暂停时布局
    /// 会回到对半，这是「不加字段」的必然结果，已与用户确认过。
    /// 用户一旦自己拖过，就一律用他的值，不再被相位改动。
    private var transcriptFraction: CGFloat {
        if let userTranscriptFraction { return userTranscriptFraction }
        return store.recordingID == nil
            ? MeetingMetrics.idleTranscriptFraction
            : MeetingMetrics.recordingTranscriptFraction
    }

    var body: some View {
        GeometryReader { geometry in
            // 门槛与任务页/笔记页共用同一个值。内容区宽度不够两栏时退化成单栏，
            // 否则列表列会被 `maximum` 顶到 listMinimum、详情栏被挤成负宽度。
            let wide = geometry.size.width >= WFMetrics.splitMinimum
            let maximum = max(WFMetrics.listMinimum, min(WFMetrics.listMaximum,
                geometry.size.width - WFMetrics.inspectorMinimum - WFMetrics.divider))
            let width = min(max(paneWidth, WFMetrics.listMinimum), maximum)
            HStack(spacing: 0) {
                if wide || !detailOnly || store.selected == nil {
                    list(compact: !wide).frame(width: wide ? width : nil)
                        .frame(maxWidth: wide ? nil : .infinity)
                }
                if wide || (detailOnly && store.selected != nil) {
                    if wide { listDivider(width: width, maximum: maximum) }
                    detailPane
                }
            }
        }
        .background(WFColors.content)
        .sheet(isPresented: $settingsPresented) { settings }
    }

    /// 列表列与详情栏之间那条线。与任务页/笔记页同一条可拖分隔条（原来是系统
    /// `Divider()`，既拖不动、又比另外两页那条线深一档）。
    private func listDivider(width: CGFloat, maximum: CGFloat) -> some View {
        Rectangle().fill(WFColors.border).frame(width: WFMetrics.divider)
            .overlay {
                Color.clear.frame(width: WFSpace.sm).contentShape(Rectangle())
                    .onHover { inside in
                        if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
                    .gesture(DragGesture(minimumDistance: 1).onChanged { value in
                        if listDragOrigin == nil { listDragOrigin = width }
                        paneWidth = min(max((listDragOrigin ?? width) + value.translation.width,
                                            WFMetrics.listMinimum), maximum)
                    }.onEnded { _ in listDragOrigin = nil })
            }
    }

    /// 详情栏内部那条线。`vertical` 为真时左右分（拖的是宽度），否则上下分（拖的是高度）。
    /// `span` 是容器在拖动方向上的总长，`fraction` 是**被拖动那一侧**占的比例——
    /// 存比例而不是存绝对值，窗口缩放时两栏才会一起变，不会一边撑满一边挤没。
    private func splitDivider(vertical: Bool,
                              span: CGFloat,
                              fraction: Binding<CGFloat>) -> some View {
        Rectangle()
            .fill(WFColors.border)
            .frame(width: vertical ? WFMetrics.divider : nil,
                   height: vertical ? nil : WFMetrics.divider)
            .overlay {
                Color.clear
                    .frame(width: vertical ? WFSpace.sm : nil,
                           height: vertical ? nil : WFSpace.sm)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside {
                            (vertical ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    .gesture(DragGesture(minimumDistance: 1).onChanged { value in
                        guard span > 0 else { return }
                        if splitDragOrigin == nil { splitDragOrigin = fraction.wrappedValue }
                        let delta = vertical ? value.translation.width : value.translation.height
                        fraction.wrappedValue = min(
                            max((splitDragOrigin ?? fraction.wrappedValue) + delta / span,
                                MeetingMetrics.minFraction),
                            MeetingMetrics.maxFraction)
                    }.onEnded { _ in splitDragOrigin = nil })
            }
    }

    // MARK: - 列表列

    private func list(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: WFSpace.sm) {
            HStack(spacing: WFSpace.sm) {
                if compact, store.selected != nil {
                    Button { detailOnly = false } label: { Image(systemName: "chevron.left") }
                        .buttonStyle(.plain).help("返回会议列表")
                }
                Text("会议纪要").font(WFType.pageTitle)
                Spacer(minLength: WFSpace.sm)
                // 与笔记页的「新建」同一个样式：28×28、白字、accent 底、圆角 6。
                Button { store.create() } label: {
                    Image(systemName: "plus").frame(width: 28, height: 28)
                }
                .buttonStyle(.plain).foregroundStyle(.white)
                .background(WFColors.accent, in: RoundedRectangle(cornerRadius: 6))
                .help("新建会议").accessibilityLabel("新建会议")
            }
            .frame(height: 44)

            ScrollView {
                // 行距 0：与任务列表、笔记列表同口径（分割线画在行内底边，不占行距）。
                LazyVStack(spacing: 0) {
                    if store.meetings.isEmpty {
                        Text("还没有会议记录")
                            .font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, WFSpace.md)
                            .padding(.top, WFSpace.xl)
                    }
                    ForEach(store.meetings) { meeting in
                        row(meeting)
                    }
                }
            }

            Divider().padding(.horizontal, WFSpace.md)

            // 原来是一个裸 `Button("Pi 接入设置")` 贴在白条上，像个走错片场的链接。
            // 它是这一模块的设置入口，按「导航行」的样子做：图标 + 文字 + 整行可点。
            Button { settingsPresented = true } label: {
                HStack(spacing: WFSpace.inline) {
                    Image(systemName: "gearshape")
                    Text("Pi 接入设置").font(WFType.supporting)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(WFColors.secondaryText)
                .padding(.horizontal, WFSpace.md)
                .frame(height: 30)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("配置 Pi 可执行文件、模型与音频扩展")
        }
        .padding(.horizontal, WFSpace.control)
        .padding(.bottom, WFSpace.lg)
    }

    private func row(_ meeting: MeetingRecord) -> some View {
        let selected = store.selectedID == meeting.id
        return HStack(spacing: 0) {
          Button {
            store.selectedID = meeting.id
            detailOnly = true
        } label: {
            VStack(alignment: .leading, spacing: WFSpace.xs) {
                Text(meeting.title.isEmpty ? "未命名会议" : meeting.title)
                    .font(WFType.listTitleMedium)
                    .foregroundStyle(WFColors.text)
                    .lineLimit(1)
                HStack(spacing: WFSpace.sm) {
                    Text(meeting.createdAt.formatted(
                        .dateTime.month().day().hour().minute().locale(.appDate)))
                        .font(WFType.listMeta).foregroundStyle(WFColors.secondaryText)
                    if store.recordingID == meeting.id {
                        Label("录音中", systemImage: "record.circle")
                            .font(WFType.listMeta).foregroundStyle(WFColors.danger)
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, WFSpace.md)
            .padding(.vertical, WFMetrics.rowVerticalPadding)
            .frame(minHeight: WFMetrics.rowHeight, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          Button {
              if store.delete(meeting.id) { hoveredMeetingID = nil }
          } label: {
              Image(systemName: "trash")
                  .font(WFType.supporting)
                  .frame(width: 28, height: 28)
                  .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .foregroundStyle(WFColors.secondaryText)
          .disabled(!store.canDelete(meeting.id))
          .opacity(hoveredMeetingID == meeting.id ? (store.canDelete(meeting.id) ? 1 : 0.4) : 0)
          .allowsHitTesting(hoveredMeetingID == meeting.id)
          .accessibilityHidden(hoveredMeetingID != meeting.id)
          .accessibilityLabel("删除会议记录：\(meeting.title.isEmpty ? "未命名会议" : meeting.title)")
          .help(store.canDelete(meeting.id) ? "删除会议记录" : "请结束录音及转写后再删除")
          .padding(.trailing, WFSpace.md)
        }
        .background(selected ? WFColors.listSelection : .clear,
                    in: RoundedRectangle(cornerRadius: WFMetrics.corner))
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { hoveredMeetingID = meeting.id }
            else if hoveredMeetingID == meeting.id { hoveredMeetingID = nil }
        }
        // 选中行不画分割线：选中行有自己的圆角底色，线会横穿底边。
        // 与笔记列表同一条线、同一个左右内缩。
        .overlay(alignment: .bottom) {
            if !selected {
                ListRowDivider(leading: ListRowMetrics.notesDividerLeading,
                               trailing: ListRowMetrics.notesDividerLeading)
            }
        }
    }

    // MARK: - 详情栏

    @ViewBuilder private var detailPane: some View {
        if let meeting = store.selected {
            detail(meeting)
        } else {
            emptyState
        }
    }

    /// 空态对齐倒数纪念日页的范式（同为 rail-only 目的地）：符号 + 标题 + 说明，
    /// 全部 `secondaryText`，居中。
    private var emptyState: some View {
        VStack(spacing: WFSpace.md) {
            VStack(spacing: WFSpace.md) {
                Image(systemName: NativeDestination.meetings.symbol).font(.largeTitle)
                Text("记录对话，持续整理同一份纪要").font(WFType.body)
                Text("音频不保存；实时采集与转写需要 Pi 音频扩展。").font(WFType.supporting)
            }
            .foregroundStyle(WFColors.secondaryText)
            Button("新建会议") { store.create() }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .padding(.top, WFSpace.sm)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func detail(_ meeting: MeetingRecord) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // 工具行与标题块横跨两栏：录音控制与会议身份属于整场会议，不属于某一栏。
            toolbar(meeting)
            Divider()
            titleBlock(meeting)
                .padding(.horizontal, WFSpace.xl)
                .padding(.vertical, WFSpace.md)
            if let error = store.error {
                errorBanner(error)
                    .padding(.horizontal, WFSpace.xl)
                    .padding(.bottom, WFSpace.md)
            }
            Divider()
            contentSplit(meeting)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 详情栏内部的两栏。宽度够就左右分（转写在左），不够就上下分（纪要在上）——
    /// 两种形态都同时看得见两样东西，任何宽度下都不再把其中一样藏进 tab 里。
    private func contentSplit(_ meeting: MeetingRecord) -> some View {
        GeometryReader { geometry in
            let size = geometry.size
            if size.width >= MeetingMetrics.splitMinimum {
                let left = min(max(size.width * transcriptFraction,
                                   size.width * MeetingMetrics.minFraction),
                               size.width * MeetingMetrics.maxFraction)
                HStack(spacing: 0) {
                    transcriptColumn(meeting).frame(width: left)
                    splitDivider(vertical: true, span: size.width,
                                 fraction: Binding(get: { transcriptFraction },
                                                   set: { userTranscriptFraction = $0 }))
                    minutesColumn(meeting).frame(maxWidth: .infinity)
                }
                // 只给「相位切换」这一件事加动画：拖分割线时不走这条，
                // 否则拖动会带上 0.22s 的滞后，手感变糊。
                .animation(.easeInOut(duration: 0.22), value: store.recordingID)
            } else {
                let top = min(max(size.height * minutesFraction,
                                  size.height * MeetingMetrics.minFraction),
                              size.height * MeetingMetrics.maxFraction)
                VStack(spacing: 0) {
                    minutesColumn(meeting).frame(height: top)
                    splitDivider(vertical: false, span: size.height,
                                 fraction: $minutesFraction)
                    transcriptColumn(meeting).frame(maxHeight: .infinity)
                }
            }
        }
    }

    /// 详情栏工具行：44pt，与笔记检查器那一条同高。录音控制住在这一条里，
    /// 正文区因此只剩下「内容」，不再被一排按钮切断。
    private func toolbar(_ meeting: MeetingRecord) -> some View {
        HStack(spacing: WFSpace.md) {
            if store.recordingID == meeting.id {
                Label("录音中", systemImage: "record.circle")
                    .font(WFType.supporting).foregroundStyle(WFColors.danger)
                Button("暂停录音") { store.stopRecording() }.controlSize(.small)
            } else {
                Button(meeting.duration == 0 ? "开始录音" : "继续录音") {
                    _Concurrency.Task { await store.startRecording() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.recordingID != nil || store.requestingPermission || store.transcribing)
            }
            if store.requestingPermission {
                ProgressView().controlSize(.small)
                Text("正在准备录音").font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
                Button("取消等待") { store.stopRecording() }.controlSize(.small)
            }
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Text("已采集 \(store.recordedSeconds(meeting)) 秒")
                    .font(WFType.listMeta).foregroundStyle(WFColors.secondaryText)
                    .monospacedDigit()
            }
            Spacer(minLength: WFSpace.sm)
            if store.transcribing {
                ProgressView().controlSize(.small)
                Text("Pi 转写中").font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
            }
            if store.updatingMinutes {
                ProgressView().controlSize(.small)
                Text("Pi 更新纪要中").font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
            }
        }
        .padding(.horizontal, WFSpace.xl)
        .frame(height: 44)
    }

    private func titleBlock(_ meeting: MeetingRecord) -> some View {
        VStack(alignment: .leading, spacing: WFSpace.xs) {
            TextField("会议标题", text: Binding(get: { store.selected?.title ?? "" }, set: store.rename))
                .textFieldStyle(.plain).font(WFType.detailTitle)
                .accessibilityLabel("会议标题")
            Text(meeting.createdAt.formatted(
                .dateTime.year().month().day().hour().minute().locale(.appDate)))
                .font(WFType.caption).foregroundStyle(WFColors.secondaryText)
            Text(store.audioConfigured
                 ? (store.configuration.usesHTTPTranscription
                    ? "Pi HTTP 分段转写：约 10–20 秒提交一次，停止时补发尾段。讲话人标签仅在当前片段内有效；音频不保存，纪要手动编辑。"
                    : "内置 Pi 扩展支持流式转写：草稿实时修正，定稿后进入对话记录。讲话人暂未区分。自定义扩展使用分段转写；音频均不保存。")
                 : "尚未配置 Pi 音频扩展，不能开始采集。只保存文字和纪要，不保存录音。")
                .font(WFType.caption).foregroundStyle(WFColors.secondaryText)
                .padding(.top, WFSpace.xs)
        }
    }

    private func errorBanner(_ error: String) -> some View {
        HStack(alignment: .top, spacing: WFSpace.sm) {
            Image(systemName: "exclamationmark.circle").foregroundStyle(WFColors.danger)
            Text(error).font(WFType.supporting).foregroundStyle(WFColors.danger)
                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: WFSpace.sm)
            Button("关闭提示") { store.error = nil }
                .buttonStyle(.borderless).font(WFType.supporting)
        }
        .padding(WFSpace.md)
        .background(WFColors.danger.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: WFMetrics.corner))
    }

    // MARK: - 左栏：对话记录

    private func transcriptColumn(_ meeting: MeetingRecord) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            columnHeader("对话记录", trailing: transcriptSummary(meeting))
            Divider()
            // 自己一条滚动条。原来整页共用一条外层 `ScrollView`，
            // 分栏之后两栏必须各滚各的，否则一边滚另一边跟着动。
            //
            // 贴底自动跟随：录音过程中新行、草稿更新不断追加，不滚的话最新
            // 内容永远在折叠线以下（用户反馈 #4）。贴底判断靠底部哨兵与视口
            // 两个 preference 相减；用户上翻超过阈值就停止跟随。
            ScrollViewReader { proxy in
                ScrollView {
                    transcript(meeting)
                        .padding(.vertical, WFSpace.xs)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .bottom) { bottomSentinel }
                }
                .coordinateSpace(name: Self.transcriptSpace)
                .background(viewportProbe)
                .onPreferenceChange(TranscriptBottomKey.self) {
                    transcriptContentBottom = $0
                    syncPinned()
                }
                .onPreferenceChange(TranscriptViewportKey.self) {
                    transcriptViewportHeight = $0
                    syncPinned()
                }
                .onAppear {
                    proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
                }
                .onChange(of: meeting.id) { _, _ in
                    // 换会议：无条件回底部并恢复跟随；等新内容布完局再跳。
                    transcriptPinned = true
                    DispatchQueue.main.async {
                        proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
                    }
                }
                .onChange(of: transcriptTail(meeting)) { _, _ in
                    guard transcriptPinned else { return }
                    withAnimation(.easeOut(duration: 0.18)) {
                        proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func syncPinned() {
        transcriptPinned = transcriptContentBottom
            <= transcriptViewportHeight + Self.autoFollowThreshold
    }

    /// 触发指纹：行数 + 最后一行身份 + 草稿文本。草稿每条 delta 都在变，
    /// 直接拿字典当 onChange 值既要求 Equatable 又太重，拼个轻量字符串足够。
    private func transcriptTail(_ meeting: MeetingRecord) -> String {
        let drafts = store.streamDrafts[meeting.id]?.values
            .map(\.text).sorted().joined(separator: "\u{1}") ?? ""
        return "\(meeting.transcript.count)|\(meeting.transcript.last?.id.uuidString ?? "")|\(drafts)"
    }

    private var bottomSentinel: some View {
        Color.clear
            .frame(height: 1)
            .id(Self.bottomAnchorID)
            .background(GeometryReader { geo in
                Color.clear.preference(key: TranscriptBottomKey.self,
                                       value: geo.frame(in: .named(Self.transcriptSpace)).maxY)
            })
    }

    private var viewportProbe: some View {
        GeometryReader { geo in
            Color.clear.preference(key: TranscriptViewportKey.self, value: geo.size.height)
        }
    }

    /// 头部右侧的进度：「12 段 · 3 段未进纪要」。分栏之后这条信息才有地方放。
    ///
    /// 手动接管纪要之后不再报「几段未进纪要」——Pi 已经不跟进了，这个数只会一直涨，
    /// 报出来等于承诺一件不会发生的事。退回只报总段数。
    private func transcriptSummary(_ meeting: MeetingRecord) -> String? {
        guard !meeting.transcript.isEmpty else { return nil }
        guard !meeting.minutesIsManual else { return "\(meeting.transcript.count) 段" }
        let pending = meeting.transcript.count - meeting.summarizedLineCount
        return pending > 0
            ? "\(meeting.transcript.count) 段 · \(pending) 段未进纪要"
            : "\(meeting.transcript.count) 段"
    }

    private func transcript(_ meeting: MeetingRecord) -> some View {
        let done = Set(meeting.summarizedLineIDs)
        // 手动接管后没有「未进纪要」这回事，分界线一并撤掉。
        let boundary = meeting.minutesIsManual
            ? nil
            : meeting.transcript.firstIndex { !done.contains($0.id) }
        return VStack(alignment: .leading, spacing: 0) {
            if meeting.transcript.isEmpty && (store.streamDrafts[meeting.id]?.isEmpty ?? true) {
                Text("尚无对话文字。录音不会被当作已转写。")
                    .font(WFType.body).foregroundStyle(WFColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, WFSpace.md)
            }
            ForEach(Array(meeting.transcript.enumerated()), id: \.element.id) { index, line in
                // Pi 是按顺序总结的，所以「已进纪要 / 未进纪要」的分界就在第一条
                // 未被总结的行之前。`summarizedLineIDs` 是现成的，不用新加字段。
                if index == boundary, let boundary, boundary > 0 {
                    pendingBoundary(meeting.transcript.count - meeting.summarizedLineCount)
                }
                transcriptRow(line,
                              showsSpeaker: index == 0
                                  || meeting.transcript[index - 1].speaker != line.speaker,
                              inMinutes: done.contains(line.id))
            }
            ForEach((store.streamDrafts[meeting.id]?.values.map { $0 } ?? []).sorted { $0.offset < $1.offset }) { line in
                VStack(alignment: .leading, spacing: WFSpace.xs) {
                    Text("正在转写 · 草稿").font(WFType.caption).foregroundStyle(WFColors.secondaryText)
                    transcriptRow(line)
                }
                .opacity(0.7)
                .accessibilityLabel("实时转写草稿：\(line.text)")
            }
        }
    }

    /// 一条转写。时间与说话人各占一列、正文一列——分栏之后每栏只有一半宽，
    /// 「说话人+时刻」再单独占一行会把每条都撑成两行，扫读也看不出谁在什么时候说的。
    ///
    /// - `showsSpeaker`：**连续同一个人说话时，后面几行不再重复写名字**。列宽照占，
    ///   所以正文仍然对齐，读者靠留白就能看出「还是他」。原来每条都写「李工」，
    ///   连说四句就是四个「李工」，很吵。
    /// - `inMinutes`：这一行**已经进了纪要**，左侧画一条 2pt 强调色竖线。
    ///   原来只有那条横向分界线，一滚出屏幕就失了锚——这条竖线跟着行走，
    ///   所以不靠滚动位置也能看出哪些进了纪要。
    private func transcriptRow(_ line: MeetingTranscriptLine,
                               showsSpeaker: Bool = true,
                               inMinutes: Bool = false) -> some View {
        HStack(alignment: .top, spacing: WFSpace.sm) {
            Text(timestamp(line.offset))
                .font(WFType.caption).foregroundStyle(WFColors.tertiaryText)
                .monospacedDigit()
                .frame(width: MeetingMetrics.timeColumn, alignment: .trailing)
            Text(showsSpeaker ? line.speaker : "")
                .font(WFType.caption).foregroundStyle(WFColors.secondaryText)
                .lineLimit(1).truncationMode(.tail)
                .frame(width: MeetingMetrics.speakerColumn, alignment: .leading)
            Text(line.text)
                .font(WFType.body)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, WFSpace.md)
        .padding(.vertical, WFSpace.xs)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(inMinutes ? WFColors.accent : Color.clear)
                .frame(width: MeetingMetrics.inMinutesBar)
        }
    }

    /// 「以下 N 段尚未进入纪要」的分界线。
    ///
    /// **只画线、不把下面的字调淡**：未进纪要的是**最新**的几段，不是最不重要的几段。
    /// 调淡会读成「过期 / 已禁用」，方向正好反了。
    private func pendingBoundary(_ count: Int) -> some View {
        HStack(spacing: WFSpace.sm) {
            Rectangle().fill(WFColors.listRowSeparator)
                .frame(height: WFMetrics.divider)
                .frame(maxWidth: .infinity)
            Text("以下 \(count) 段尚未进入纪要")
                .font(WFType.caption).foregroundStyle(WFColors.tertiaryText)
                .fixedSize()
            Rectangle().fill(WFColors.listRowSeparator)
                .frame(height: WFMetrics.divider)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, WFSpace.md)
        .padding(.vertical, WFSpace.sm)
    }

    // MARK: - 右栏：滚动纪要

    private func minutesColumn(_ meeting: MeetingRecord) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            columnHeader("滚动纪要", trailing: minutesHeaderTrailing(meeting))
            Divider()
            minutesEditor(meeting)
            Divider()
            minutesFooter(meeting)
        }
    }

    /// 表头右侧：自动模式下报「更新于 hh:mm」，手动接管后改成说明状态。
    /// 两者互斥——手动接管后 `minutesUpdatedAt` 停在接管前的时刻，再报它就没有意义了。
    private func minutesHeaderTrailing(_ meeting: MeetingRecord) -> String? {
        if meeting.minutesIsManual { return "已手动编辑" }
        return meeting.minutesUpdatedAt.map {
            "更新于 \($0.formatted(.dateTime.hour().minute().locale(.appDate)))"
        }
    }

    /// 纪要正文：**直接可编辑**，不再是一个只读投影 + 「更新纪要」按钮。
    ///
    /// 自己就是一块 `TextEditor`，所以**外面不要再套 `ScrollView`**——两者都带滚动条，
    /// 套起来会出现「外层滚不动、内层滚到头」的夹层手感。
    ///
    /// 代价：`TextEditor` 显示的是 Markdown 源码，原来那套渲染过的标题/项目符号没有了。
    /// 这是「可编辑」换来的，取舍点在这里。
    private func minutesEditor(_ meeting: MeetingRecord) -> some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: Binding(
                get: { store.selected?.minutes ?? "" },
                set: { store.editMinutes($0) }
            ))
            .font(WFType.body)
            .scrollContentBackground(.hidden)
            .background(WFColors.content)
            .accessibilityLabel("会议纪要")
            // `TextEditor` 没有 placeholder，按项目里既有的做法自己叠一层
            // （`SummaryWorkspaceView` 的日记/周报两处都是这个写法）。
            if meeting.minutes.isEmpty {
                Text("有对话文字后，Pi 会持续更新这里的纪要；也可以直接在这里写。")
                    .font(WFType.body).foregroundStyle(WFColors.tertiaryText)
                    .padding(.top, WFSpace.sm)
                    .padding(.leading, WFSpace.xs)
                    .allowsHitTesting(false)
            }
        }
        .padding(WFSpace.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 底栏。原来这里是「更新纪要 + 复制纪要」——纪要可直接编辑之后，
    /// 那个按钮就没有存在意义了，删掉。留下的是「复制」和一条退路。
    private func minutesFooter(_ meeting: MeetingRecord) -> some View {
        HStack(spacing: WFSpace.sm) {
            Button("复制纪要") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(meeting.minutes, forType: .string)
            }
            .controlSize(.small)
            .disabled(meeting.minutes.isEmpty)
            Spacer(minLength: WFSpace.sm)
            // 手动接管是**单向**的：不给人退路的话，误敲一个字就永远失去自动更新。
            // 所以只在接管状态下露出这一条，不常驻无效操作——
            // 只在真能做点什么的时候出现。
            if meeting.minutesIsManual {
                Text("Pi 已停止自动更新")
                    .font(WFType.caption).foregroundStyle(WFColors.secondaryText)
                Button("交回自动更新") { store.resumeAutomaticMinutes() }
                    .controlSize(.small)
                    .help("把这份纪要交回给 Pi 继续维护；你写的内容会保留，作为下次更新的基础")
            }
        }
        .padding(.horizontal, WFSpace.md)
        .frame(height: MeetingMetrics.columnFooterHeight)
    }

    // MARK: - 共用小件

    /// 两栏各自的表头：标题在左、进度在右，30pt。
    ///
    /// **不加底色。** 试过 `WFColors.secondarySurface`，两处都不成立，已回退：
    /// ① 它是 `NSColor.controlBackgroundColor`，浅色外观下解出来就是**纯白**，
    ///    和 `content` 的白底没有明度差——实测表头带像素 `(255,255,255)`，等于没加；
    /// ② 全项目没有任何一页给表头带填色（侧栏/任务管理面板的 `sectionHeader` 都是
    ///    纯文字 + 内边距），加了反而和自家不一致；
    /// ③ 而且这一条本来就是我的误判——表头下面**已经有** `Divider()`（实测表头带
    ///    下沿 y=212 处有一条 1px 灰线），并不「与正文糊在一起」。
    private func columnHeader(_ title: String, trailing: String? = nil) -> some View {
        HStack(spacing: WFSpace.sm) {
            Text(title).font(WFType.sectionSemibold)
            if let trailing {
                Text(trailing)
                    .font(WFType.caption).foregroundStyle(WFColors.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, WFSpace.md)
        .frame(height: MeetingMetrics.columnHeaderHeight)
    }

    private func timestamp(_ offset: TimeInterval) -> String {
        let total = Int(offset)
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }

    // MARK: - Pi 接入设置

    private var settings: some View {
        VStack(alignment: .leading, spacing: WFSpace.lg) {
            Text("Pi 会议接入").font(WFType.detailTitle)
            Text("所有 AI 调用经过本机 Pi。百炼实时模型走流式转写；qwen-audio-3.1-asr-flash 走 HTTP 分段转写。ASR 模型不能生成纪要，可手动编辑。")
                .font(WFType.body).foregroundStyle(WFColors.secondaryText)
            VStack(alignment: .leading, spacing: WFSpace.lg) {
                settingField("Pi 可执行文件", placeholder: "Pi 可执行文件",
                             text: $store.configuration.executable)
                settingField("模型标识（百炼实时或 HTTP ASR）", placeholder: "留空沿用 Pi 当前实时模型",
                             text: $store.configuration.model)
                settingField("Pi 音频扩展（可选覆盖）", placeholder: "留空使用内置 Pi 音频扩展",
                             text: $store.configuration.audioExtension)
            }
            .disabled(store.transcribing || store.updatingMinutes || store.recordingID != nil)
            Text("默认使用内置 Pi 扩展，端点与认证由 Pi 提供。使用 HTTP ASR 时请明确填写模型标识；自定义扩展路径可替换内置接入。音频不保存；讲话人标签仅在当前片段内区分，不保证跨片段为同一人。")
                .font(WFType.caption).foregroundStyle(WFColors.secondaryText)
            HStack {
                Spacer()
                Button("完成") { settingsPresented = false }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }
        .padding(WFSpace.xxl)
        .frame(width: 550)
    }

    private func settingField(_ label: String, placeholder: String,
                              text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: WFSpace.sm) {
            Text(label).font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
            TextField(placeholder, text: text).accessibilityLabel(label)
        }
    }
}

/// 对话记录贴底跟随的两个量：内容底边在滚动区坐标里的位置，和视口高度。
/// 相减小于阈值即视为贴底（见 `MeetingWorkspaceView.transcriptColumn`）。
private struct TranscriptBottomKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct TranscriptViewportKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
