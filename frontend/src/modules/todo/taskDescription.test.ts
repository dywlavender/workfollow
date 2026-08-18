import { describe, expect, it } from 'vitest'

import { taskDescriptionText } from '@/modules/todo/taskDescription'
import { LONG_HTML_TASK_DESCRIPTION } from '@/test/fixtures/taskDescription'

describe('taskDescriptionText', () => {
  it('converts legacy HTML into plain text', () => {
    expect(taskDescriptionText('<p>第一段</p><p>第二段</p>')).toBe('第一段 第二段')
  })

  it('does not render empty HTML', () => {
    expect(taskDescriptionText('<p><br></p><div>&nbsp;</div>')).toBe('')
  })

  it('decodes named, decimal, and hexadecimal entities', () => {
    expect(taskDescriptionText('研发&amp;测试 &#20320;&#x597D; &lt;完成&gt;')).toBe('研发&测试 你好 <完成>')
  })

  it('flattens nested blocks without joining words together', () => {
    expect(taskDescriptionText('<div>计划<ul><li><strong>设计</strong></li><li>开发</li></ul></div>')).toBe('计划 设计 开发')
  })

  it('removes malicious elements, tags, and attributes', () => {
    expect(taskDescriptionText('<p onclick="steal()">安全</p><script>alert(1)</script><img src=x onerror=steal()>')).toBe('安全')
  })

  it('keeps long text intact for CSS line clamping', () => {
    const result = taskDescriptionText(LONG_HTML_TASK_DESCRIPTION)
    expect(result).not.toContain('<')
    expect(result.length).toBeGreaterThan(100)
    expect(result).toContain('第一项：标签不能直接显示。')
    expect(result).toContain('第二项：& 等实体应正确解码。')
  })

  it('falls back to ProseMirror content when description is empty', () => {
    expect(taskDescriptionText(null, {
      type: 'doc',
      content: [{ type: 'paragraph', content: [{ type: 'text', text: '正文' }, { type: 'hardBreak' }, { type: 'text', text: '下一行' }] }],
    })).toBe('正文 下一行')
  })
})
