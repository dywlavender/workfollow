export type WorkFollowSlashCommand = 'h1' | 'h2' | 'h3' | 'ul' | 'ol' | 'check' | 'quote' | 'code' | 'hr' | 'table' | 'link' | 'attachment' | 'subtask' | 'tag' | 'relation' | 'createTask' | 'linkTask'

export interface WorkFollowSlashCommandItem {
  type: WorkFollowSlashCommand
  label: string
  mark: string
  noteOnly?: boolean
}

/** The single command vocabulary shared by task and note body editors. */
export const workFollowSlashCommands: WorkFollowSlashCommandItem[] = [
  { type: 'h1', label: '一级标题', mark: 'H1' },
  { type: 'h2', label: '二级标题', mark: 'H2' },
  { type: 'h3', label: '三级标题', mark: 'H3' },
  { type: 'ul', label: '无序列表', mark: '•' },
  { type: 'ol', label: '有序列表', mark: '1.' },
  { type: 'check', label: '清单', mark: '☑' },
  { type: 'quote', label: '引用', mark: '❝' },
  { type: 'code', label: '代码块', mark: '</>' },
  { type: 'hr', label: '水平分割线', mark: '—' },
  { type: 'table', label: '表格', mark: '▦' },
  { type: 'link', label: '链接', mark: '↗' },
  { type: 'attachment', label: '附件', mark: '↥' },
  { type: 'subtask', label: '子代办', mark: '↳' },
  { type: 'tag', label: '标签', mark: '#' },
  { type: 'relation', label: '关联代办 / 笔记', mark: '↗' },
  { type: 'createTask', label: '创建代办', mark: '✓', noteOnly: true },
  { type: 'linkTask', label: '关联已有代办', mark: '↗', noteOnly: true },
]
