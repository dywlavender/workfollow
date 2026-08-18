export const LONG_HTML_TASK_DESCRIPTION = [
  '<div data-test="long-task-description">',
  '<h2>响应式任务摘要复验</h2>',
  '<p>这是一段足够长的旧版 HTML 任务说明，用于检查任务列表只显示纯文本摘要，并在窄屏和宽屏下稳定限制为最多两行。</p>',
  '<ul><li><strong>第一项：</strong>标签不能直接显示。</li><li>第二项：&amp; 等实体应正确解码。</li></ul>',
  '<p>末尾继续增加内容，确保测试数据能够触发省略，而不会写入或污染真实数据库。</p>',
  '</div>',
].join('')
