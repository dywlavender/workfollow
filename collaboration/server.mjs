import { Server } from '@hocuspocus/server'
import { ProsemirrorTransformer, TiptapTransformer } from '@hocuspocus/transformer'
import { Schema } from '@tiptap/pm/model'
import * as Y from 'yjs'
import { fileURLToPath } from 'node:url'
import { mkdir, readFile, readdir, rename, unlink, writeFile } from 'node:fs/promises'
import { randomUUID } from 'node:crypto'
import path from 'node:path'

const projectDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const projectEnvPath = path.join(projectDir, '.env')

// FastAPI already reads the root .env file. Load that same file here so the
// collaboration process has one configuration source and does not require a
// second token argument when it is started from the collaboration directory.
try {
  process.loadEnvFile(projectEnvPath)
} catch (error) {
  if (error?.code !== 'ENOENT') throw error
}

const port = Number.parseInt(process.env.WORKFOLLOW_COLLABORATION_PORT ?? '8124', 10)
const address = process.env.WORKFOLLOW_COLLABORATION_BIND ?? '127.0.0.1'
const backendUrl = (process.env.WORKFOLLOW_BACKEND_URL ?? 'http://127.0.0.1:8123').replace(/\/$/, '')
const dataDir = path.resolve(process.env.WORKFOLLOW_COLLABORATION_DATA_DIR ?? path.join(projectDir, 'data', 'collaboration'))
const internalToken = process.env.WORKFOLLOW_COLLABORATION_INTERNAL_TOKEN ?? ''

if (!Number.isInteger(port) || port < 1 || port > 65535) {
  throw new Error('WORKFOLLOW_COLLABORATION_PORT 必须是 1-65535 的整数')
}
if (!internalToken) {
  throw new Error('WORKFOLLOW_COLLABORATION_INTERNAL_TOKEN 未配置')
}

await mkdir(dataDir, { recursive: true })

function documentInfo(documentName) {
  const bodyMatch = /^task:([A-Za-z0-9-]{1,64})$/.exec(documentName)
  if (bodyMatch) return { resource: 'task', taskId: bodyMatch[1], kind: 'body' }
  const metadataMatch = /^task-meta:([A-Za-z0-9-]{1,64})$/.exec(documentName)
  if (metadataMatch) return { resource: 'task', taskId: metadataMatch[1], kind: 'metadata' }
  const noteMatch = /^note:([A-Za-z0-9-]{1,64})$/.exec(documentName)
  if (noteMatch) return { resource: 'note', noteId: noteMatch[1], kind: 'note' }
  const knowledgeMatch = /^knowledge-draft:([A-Za-z0-9-]{1,64})$/.exec(documentName)
  if (knowledgeMatch) return { resource: 'knowledge', noteId: knowledgeMatch[1], kind: 'knowledge-draft' }
  throw new Error('非法的协同文档名')
}

function statePath(info) {
  // Keep the original body filename so existing Yjs body snapshots remain
  // readable after metadata gets its own document.
  const filename = info.resource === 'task'
    ? (info.kind === 'body' ? `${info.taskId}.bin` : `metadata-${info.taskId}.bin`)
    : `${info.resource}-${info.noteId}.bin`
  return path.join(dataDir, filename)
}

async function loadStoredState(info) {
  try {
    return new Uint8Array(await readFile(statePath(info)))
  } catch (error) {
    if (error?.code === 'ENOENT') return undefined
    throw error
  }
}

async function storeState(info, update) {
  const target = statePath(info)
  const temporary = `${target}.tmp`
  await writeFile(temporary, update)
  await rename(temporary, target)
}

function pendingProjectionPath(info) {
  return `${statePath(info)}.pending`
}

async function writePendingProjection(info, record) {
  const target = pendingProjectionPath(info)
  const temporary = `${target}.tmp`
  await writeFile(temporary, JSON.stringify(record), 'utf8')
  await rename(temporary, target)
}

async function readPendingProjection(info) {
  try {
    const raw = await readFile(pendingProjectionPath(info), 'utf8')
    const record = JSON.parse(raw)
    if (!record || record.documentName !== projectionDocumentName(info)) return undefined
    if (typeof record.state !== 'string' || !record.projectionId) return undefined
    return record
  } catch (error) {
    if (error?.code === 'ENOENT') return undefined
    throw error
  }
}

async function clearPendingProjection(info, projectionId) {
  const current = await readPendingProjection(info)
  if (!current || current.projectionId !== projectionId) return
  try {
    await unlink(pendingProjectionPath(info))
  } catch (error) {
    if (error?.code !== 'ENOENT') throw error
  }
}

// A single debounced SQL projection can contain updates from several browser
// connections. Keep those actors alongside the document until the projection
// is accepted so notification policy is based on all contributors, not only
// the last Yjs transaction.
const pendingActors = new Map()
const initializationClaims = new Map()
const INITIALIZATION_CLAIM_TTL_MS = 15_000

function rememberActor(documentName, context) {
  const actorId = context?.userId
  if (!actorId) return
  const actors = pendingActors.get(documentName) ?? new Set()
  actors.add(actorId)
  pendingActors.set(documentName, actors)
}

function initializationKey(documentName, field) {
  return `${documentName}:${field}`
}

function documentFieldInitialized(document, field) {
  if (field === 'body') {
    return document.getXmlFragment('default').length > 0
      || document.getMap('config').get('bodyInitialized') === true
  }
  if (field === 'metadata') {
    const metadata = document.getMap('metadata')
    return metadata.get('initialized') === true
      || document.getMap('config').get('metadataInitialized') === true
  }
  return false
}

function markInitializationClaims(documentName, document) {
  for (const field of ['body', 'metadata']) {
    const key = initializationKey(documentName, field)
    if (documentFieldInitialized(document, field)) initializationClaims.delete(key)
  }
}

function requestOriginAllowed(request) {
  const origin = request.headers.origin
  if (!origin) return null
  try {
    const originUrl = new URL(origin)
    const requestHost = String(request.headers.host ?? '').split(':')[0]
    const localHost = new Set(['localhost', '127.0.0.1', '::1'])
    if (originUrl.hostname === requestHost || (localHost.has(originUrl.hostname) && localHost.has(requestHost))) return origin
  } catch {
    // Invalid Origin headers simply do not receive CORS permission.
  }
  return null
}

function writeCorsHeaders(request, response) {
  const origin = requestOriginAllowed(request)
  if (!origin) return
  response.setHeader('Access-Control-Allow-Origin', origin)
  response.setHeader('Access-Control-Allow-Credentials', 'true')
  response.setHeader('Access-Control-Allow-Headers', 'content-type')
  response.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS')
  response.setHeader('Vary', 'Origin')
}

async function backendJson(endpoint, cookie) {
  const response = await fetch(`${backendUrl}${endpoint}`, {
    headers: cookie ? { cookie } : {},
  })
  if (!response.ok) throw new Error(`后端返回 ${response.status}: ${endpoint}`)
  return response.json()
}

async function initialSeed(info, cookie) {
  if (info.resource === 'task') {
    return backendJson(`/api/tasks/${encodeURIComponent(info.taskId)}`, cookie)
  }
  if (info.resource === 'note') {
    // Owners use the personal-note endpoint; a shared-note reader is allowed
    // through the collaboration-access endpoint but is intentionally denied
    // the owner-only personal-note route. Use the read-only share projection
    // as the second, permission-checked source for that case.
    try {
      return await backendJson(`/api/notes/${encodeURIComponent(info.noteId)}`, cookie)
    } catch {
      return backendJson(`/api/shared/notes/${encodeURIComponent(info.noteId)}`, cookie)
    }
  }
  if (info.resource === 'knowledge') {
    const access = await backendJson(
      `/api/team/knowledge/${encodeURIComponent(info.noteId)}/collaboration-access`,
      cookie,
    )
    const teamId = typeof access?.teamId === 'string' && access.teamId
      ? `?teamId=${encodeURIComponent(access.teamId)}`
      : ''
    return backendJson(`/api/team/knowledge/${encodeURIComponent(info.noteId)}${teamId}`, cookie)
  }
  throw new Error('不支持的协同资源')
}

async function knowledgeStateMatchesCurrentVersion(info, state, cookie) {
  if (info.resource !== 'knowledge') return true
  try {
    const current = await backendJson(`/api/team/knowledge/${encodeURIComponent(info.noteId)}/collaboration-access`, cookie)
    const draft = new Y.Doc()
    Y.applyUpdate(draft, state)
    const baseVersion = draft.getMap('config').get('baseVersion')
    draft.destroy()
    return Number(baseVersion) === Number(current?.versionNo)
  } catch (error) {
    console.warn(`协同知识版本校验失败 document=${projectionDocumentName(info)}`, error?.message ?? error)
    return false
  }
}

/**
 * 知识草稿版本过期时，不能直接用已发布内容重新引导文档：浏览器端
 * （IndexedDB 恢复或仍连接的旧会话）还持有旧草稿，新引导的插入会与旧内容
 * 叠加成双份。这里在旧草稿 state 上构造"删光旧 title/正文 → 写入已发布
 * 内容"的重置更新，所有客户端应用后都收敛到单份。
 */
async function resetKnowledgeDraftToPublished(storedState, info, cookie) {
  const note = await initialSeed(info, cookie)
  const published = bootstrapDocument(note.contentJson, {
    title: note.title,
    metadata: {
      categoryId: note.categoryId ?? null,
      tags: Array.isArray(note.tags) ? note.tags : [],
      baseVersion: note.versionNo,
    },
  })
  const draft = new Y.Doc()
  try {
    Y.applyUpdate(draft, storedState)
    draft.transact(() => {
      const title = draft.getText('title')
      if (title.length > 0) title.delete(0, title.length)
      const fragment = draft.getXmlFragment('default')
      if (fragment.length > 0) fragment.delete(0, fragment.length)
    })
    Y.applyUpdate(draft, Y.encodeStateAsUpdate(published))
    const reset = Y.encodeStateAsUpdate(draft)
    return reset
  } finally {
    draft.destroy()
    published.destroy()
  }
}

async function readRequestBody(request, maxBytes = 16 * 1024) {
  const chunks = []
  let length = 0
  for await (const chunk of request) {
    length += chunk.length
    if (length > maxBytes) throw new Error('协同请求过大')
    chunks.push(chunk)
  }
  if (!chunks.length) return {}
  return JSON.parse(Buffer.concat(chunks).toString('utf8'))
}

function documentVersion(document) {
  return Buffer.from(Y.encodeStateVector(document)).toString('base64')
}

function replaceDocumentBody(document, contentJson) {
  const source = ProsemirrorTransformer.toYdoc(
    contentJson,
    'default',
    bootstrapSchema(contentJson),
  )
  try {
    const target = document.getXmlFragment('default')
    if (target.length > 0) target.delete(0, target.length)
    const children = source.getXmlFragment('default').toArray().map((child) => child.clone())
    if (children.length > 0) target.insert(0, children)
    document.getMap('config').set('bodyInitialized', true)
  } finally {
    source.destroy()
  }
}

function seedAgentDocument(document, info, seed) {
  if (info.kind === 'metadata') {
    const metadata = document.getMap('metadata')
    if (metadata.get('initialized') === true) return
    const title = String(seed?.title ?? '').trim()
    if (title) document.getText('title').insert(0, title)
    for (const [key, value] of Object.entries({
      dueAt: seed?.dueAt ?? null,
      dueEndAt: seed?.dueEndAt ?? null,
      priority: seed?.priority ?? 'NONE',
      reminderAt: seed?.reminderAt ?? null,
      recurrenceType: seed?.recurrenceType ?? 'NONE',
      recurrenceConfig: seed?.recurrenceConfig ?? null,
    })) metadata.set(key, value)
    const tags = Array.isArray(seed?.tags) ? seed.tags.map(String).filter(Boolean) : []
    if (tags.length > 0) document.getArray('tags').push(tags)
    metadata.set('initialized', true)
    document.getMap('config').set('metadataInitialized', true)
    return
  }
  const fragment = document.getXmlFragment('default')
  if (fragment.length > 0 || document.getMap('config').get('bodyInitialized') === true) return
  const content = info.resource === 'task' && !contentJsonHasText(seed?.contentJson) && seed?.description
    ? legacyDescriptionToContentJson(seed.description)
    : (seed?.contentJson ?? emptyEditorDocument())
  replaceDocumentBody(document, content)
  if (info.resource === 'note') {
    const title = String(seed?.title ?? '').trim()
    if (title) document.getText('title').insert(0, title)
  }
}

function agentDocumentSnapshot(document, info) {
  if (info.kind === 'metadata') {
    return { version: documentVersion(document), metadata: readMetadata(document) }
  }
  const fragment = document.getXmlFragment('default')
  return {
    version: documentVersion(document),
    ...(info.resource === 'note'
      ? { title: document.getText('title').toString().trim() || '未命名笔记' }
      : {}),
    contentJson: fragment.length > 0
      ? TiptapTransformer.fromYdoc(document, 'default')
      : emptyEditorDocument(),
  }
}

async function handleAgentDocumentRequest({ request, response, instance }) {
  if (request.method !== 'POST') {
    response.writeHead(405, { allow: 'POST' })
    response.end()
    return
  }
  if (request.headers['x-workfollow-collaboration-token'] !== internalToken) {
    response.writeHead(401, { 'content-type': 'application/json' })
    response.end(JSON.stringify({ detail: '协同服务未授权' }))
    return
  }
  const payload = await readRequestBody(request, 6 * 1024 * 1024)
  const documentName = typeof payload.documentName === 'string' ? payload.documentName : ''
  const actorId = typeof payload.actorId === 'string' ? payload.actorId : ''
  if (!documentName || !actorId) throw new Error('Agent 协同参数无效')
  const info = documentInfo(documentName)
  if (info.resource === 'knowledge') throw new Error('Agent 暂不支持更新团队知识草稿')

  const connection = await instance.openDirectConnection(documentName, {
    userId: actorId,
    userName: 'Agent',
    canEdit: true,
  })
  try {
    await connection.transact((document) => seedAgentDocument(document, info, payload.seed ?? {}))
    const document = connection.document
    if (!document) throw new Error('协同文档连接已关闭')
    const operation = payload.operation ?? 'read'
    if (operation !== 'read') {
      if (typeof payload.expectedVersion !== 'string' || payload.expectedVersion !== documentVersion(document)) {
        response.writeHead(409, { 'content-type': 'application/json', 'cache-control': 'no-store' })
        response.end(JSON.stringify({ detail: '文档版本冲突' }))
        return
      }
      if (operation === 'replace-body' || operation === 'append-body') {
        if (!payload.contentJson || typeof payload.contentJson !== 'object') throw new Error('正文格式无效')
        await connection.transact((target) => {
          const nextContent = operation === 'append-body'
            ? {
                type: 'doc',
                content: [
                  ...(agentDocumentSnapshot(target, info).contentJson.content ?? []),
                  ...(payload.contentJson.content ?? []),
                ],
              }
            : payload.contentJson
          replaceDocumentBody(target, nextContent)
          if (info.resource === 'note' && typeof payload.title === 'string') {
            const title = target.getText('title')
            if (title.length > 0) title.delete(0, title.length)
            title.insert(0, payload.title.trim() || '未命名笔记')
          }
        })
      } else if (operation === 'update-metadata' && info.kind === 'metadata') {
        await connection.transact((target) => {
          const patch = payload.metadata && typeof payload.metadata === 'object' ? payload.metadata : {}
          if (Object.hasOwn(patch, 'title')) {
            const value = String(patch.title ?? '').trim()
            if (!value) throw new Error('待办标题不能为空')
            const title = target.getText('title')
            if (title.length > 0) title.delete(0, title.length)
            title.insert(0, value)
          }
          const metadata = target.getMap('metadata')
          for (const key of ['dueAt', 'dueEndAt', 'priority', 'reminderAt', 'recurrenceType', 'recurrenceConfig']) {
            if (Object.hasOwn(patch, key)) metadata.set(key, patch[key] ?? null)
          }
          if (Object.hasOwn(patch, 'tags')) {
            const tags = target.getArray('tags')
            if (tags.length > 0) tags.delete(0, tags.length)
            const values = Array.isArray(patch.tags) ? [...new Set(patch.tags.map(String).filter(Boolean))] : []
            if (values.length > 0) tags.push(values)
          }
        })
      } else {
        throw new Error('不支持的 Agent 协同操作')
      }
    }
    const result = agentDocumentSnapshot(document, info)
    await connection.disconnect({ unloadImmediately: true })
    response.writeHead(200, { 'content-type': 'application/json', 'cache-control': 'no-store' })
    response.end(JSON.stringify(result))
  } finally {
    if (connection.document) await connection.disconnect({ unloadImmediately: true })
  }
}

async function handleInitializationRequest({ request, response, instance }) {
  writeCorsHeaders(request, response)
  if (request.method === 'OPTIONS') {
    response.writeHead(204)
    response.end()
    return
  }
  if (request.method !== 'POST') {
    response.writeHead(405, { allow: 'POST, OPTIONS' })
    response.end()
    return
  }

  const payload = await readRequestBody(request)
  const documentName = typeof payload.documentName === 'string' ? payload.documentName : ''
  const field = payload.field === 'metadata' ? 'metadata' : payload.field === 'body' ? 'body' : ''
  if (!documentName || !field) {
    response.writeHead(400, { 'content-type': 'application/json' })
    response.end(JSON.stringify({ detail: '协同初始化参数无效' }))
    return
  }

  const info = documentInfo(documentName)
  const cookie = request.headers.cookie ?? ''
  if (!cookie) {
    response.writeHead(401, { 'content-type': 'application/json' })
    response.end(JSON.stringify({ detail: '未登录' }))
    return
  }
  const connectionConfig = {}
  const context = await authorize(documentName, new Headers({ cookie }), connectionConfig)
  const document = instance.documents.get(documentName)
  if (!document) {
    response.writeHead(409, { 'content-type': 'application/json' })
    response.end(JSON.stringify({ detail: '协同文档尚未建立，请稍后重试' }))
    return
  }

  const key = initializationKey(documentName, field)
  // 团队知识草稿始终有已发布版本兜底：一个"只有初始化标记、没有任何内容"
  // 的草稿（历史上产生过这类坏快照）会让管理员永远看到空白页。这种草稿
  // 一律视为未初始化，重新走 SQL 种子流程自愈；个人笔记和任务的空正文
  // 则可能是用户刻意清空的结果，维持原判定。
  const knowledgeDraftNeedsSeed = info.resource === 'knowledge'
    && field === 'body'
    && document.getXmlFragment('default').length === 0
  if (documentFieldInitialized(document, field) && !knowledgeDraftNeedsSeed) {
    initializationClaims.delete(key)
    response.writeHead(200, { 'content-type': 'application/json', 'cache-control': 'no-store' })
    response.end(JSON.stringify({ status: 'initialized' }))
    return
  }
  const now = Date.now()
  const currentClaim = initializationClaims.get(key)
  if (currentClaim && currentClaim.expiresAt > now) {
    response.writeHead(200, { 'content-type': 'application/json', 'cache-control': 'no-store' })
    response.end(JSON.stringify({ status: 'waiting' }))
    return
  }
  if (currentClaim) initializationClaims.delete(key)
  if (!context.canEdit) {
    response.writeHead(200, { 'content-type': 'application/json', 'cache-control': 'no-store' })
    response.end(JSON.stringify({ status: 'readonly' }))
    return
  }

  const claim = { token: randomUUID(), expiresAt: now + INITIALIZATION_CLAIM_TTL_MS }
  initializationClaims.set(key, claim)
  const initial = await initialSeed(info, cookie)
  response.writeHead(200, { 'content-type': 'application/json', 'cache-control': 'no-store' })
  response.end(JSON.stringify({ status: 'claim', token: claim.token, initial }))
}

async function authorize(documentName, requestHeaders, connectionConfig) {
  const info = documentInfo(documentName)
  const cookie = requestHeaders.get('cookie') ?? ''
  if (!cookie) throw new Error('未登录')

  const user = await backendJson('/api/auth/me', cookie)
  if (info.resource === 'task') {
    const todo = await backendJson(`/api/tasks/${encodeURIComponent(info.taskId)}`, cookie)
    const canEdit = info.kind === 'metadata'
      ? Boolean(todo?.permissions?.editable)
      : Boolean(todo?.permissions?.contentEditable)
    connectionConfig.readOnly = !canEdit
    return {
      resource: info.resource,
      taskId: info.taskId,
      documentKind: info.kind,
      userId: user.id,
      userName: user.nickname || user.username,
      canEdit,
    }
  }

  let access
  if (info.resource === 'note') {
    try {
      access = await backendJson(`/api/notes/${encodeURIComponent(info.noteId)}/collaboration-access`, cookie)
    } catch {
      // A shared personal note intentionally has no owner-level access
      // response. Its share endpoint is still permission-checked and yields a
      // read-only projection, so allow that audience into the same Y.Doc.
      await backendJson(`/api/shared/notes/${encodeURIComponent(info.noteId)}`, cookie)
      access = { canView: true, canEdit: false }
    }
  } else {
    access = await backendJson(`/api/team/knowledge/${encodeURIComponent(info.noteId)}/collaboration-access`, cookie)
  }
  if (!access?.canView) throw new Error('无权访问协同文档')
  // Team knowledge uses a private working draft. Published members continue
  // to read the approved SQL projection and never see uncommitted edits.
  if (info.resource === 'knowledge' && !access.canEdit) throw new Error('只有管理员可以编辑团队知识')
  const canEdit = Boolean(access.canEdit)
  // Hocuspocus copies this flag into the established Connection after the
  // authentication hook returns.  The hook payload has connectionConfig, not
  // a live Connection object yet.
  connectionConfig.readOnly = !canEdit
  return {
    resource: info.resource,
    noteId: info.noteId,
    documentKind: info.kind,
    userId: user.id,
    userName: user.nickname || user.username,
    canEdit,
  }
}

function metadataFromTodo(todo) {
  return {
    dueAt: todo.dueAt ?? null,
    dueEndAt: todo.dueEndAt ?? null,
    priority: todo.priority ?? 'NONE',
    reminderAt: todo.reminderAt ?? null,
    recurrenceType: todo.recurrenceType ?? 'NONE',
    recurrenceConfig: todo.recurrenceConfig ?? null,
  }
}

const knownBlockNodes = new Set([
  'doc', 'paragraph', 'heading', 'blockquote', 'codeBlock', 'bulletList', 'orderedList',
  'listItem', 'taskList', 'taskItem', 'horizontalRule', 'table', 'tableRow', 'tableCell',
  'tableHeader', 'image', 'taskReference',
])
const knownInlineNodes = new Set(['text', 'hardBreak'])
const inlineContainers = new Set(['paragraph', 'heading', 'codeBlock'])

/**
 * The browser editor has a few WorkFollow-specific nodes and attributes that
 * are not part of Hocuspocus' StarterKit. Build a permissive ProseMirror
 * schema from the SQL JSON for the one-time bootstrap. The resulting Y.Xml
 * names/attributes are the same ones consumed by the browser schema; this
 * avoids requiring the collaboration service to load Vue node views.
 */
function bootstrapSchema(root) {
  const occurrences = new Map()
  const attributes = new Map()
  const marks = new Map()
  const visit = (node, parent = 'doc') => {
    if (!node || typeof node !== 'object' || typeof node.type !== 'string') return
    const type = node.type
    const parents = occurrences.get(type) ?? []
    parents.push(parent)
    occurrences.set(type, parents)
    const nodeAttributes = attributes.get(type) ?? new Set()
    Object.keys(node.attrs ?? {}).forEach((key) => nodeAttributes.add(key))
    attributes.set(type, nodeAttributes)
    for (const mark of node.marks ?? []) {
      if (!mark || typeof mark.type !== 'string') continue
      const markAttributes = marks.get(mark.type) ?? new Set()
      Object.keys(mark.attrs ?? {}).forEach((key) => markAttributes.add(key))
      marks.set(mark.type, markAttributes)
    }
    for (const child of node.content ?? []) visit(child, type)
  }
  visit(root)

  const inlineNodes = new Set(knownInlineNodes)
  for (const [type, parents] of occurrences) {
    if (!knownBlockNodes.has(type) && parents.some((parent) => inlineContainers.has(parent))) inlineNodes.add(type)
  }

  const specs = {}
  const add = (type, group, content, atom = false) => {
    const nodeAttributes = attributes.get(type) ?? new Set()
    specs[type] = {
      ...(group ? { group } : {}),
      ...(group === 'inline' ? { inline: true } : {}),
      ...(content ? { content } : {}),
      ...(atom ? { atom: true } : {}),
      ...(nodeAttributes.size
        ? { attrs: Object.fromEntries([...nodeAttributes].map((key) => [key, { default: null }])) }
        : {}),
    }
  }

  const allTypes = new Set([...occurrences.keys(), ...knownBlockNodes, ...knownInlineNodes])
  for (const type of allTypes) {
    if (type === 'doc') { add(type, null, 'block*'); continue }
    if (type === 'text') { add(type, 'inline'); continue }
    if (type === 'paragraph' || type === 'heading' || type === 'codeBlock') { add(type, 'block', 'inline*'); continue }
    if (type === 'blockquote') { add(type, 'block', 'block+'); continue }
    if (type === 'bulletList' || type === 'orderedList' || type === 'taskList') {
      add(type, 'block', type === 'taskList' ? 'taskItem+' : 'listItem+')
      continue
    }
    if (type === 'listItem' || type === 'taskItem') { add(type, 'block', 'block+'); continue }
    if (type === 'table') { add(type, 'block', 'tableRow+'); continue }
    if (type === 'tableRow') { add(type, 'block', '(tableCell|tableHeader)+'); continue }
    if (type === 'tableCell' || type === 'tableHeader') { add(type, 'block', 'block+'); continue }
    if (type === 'horizontalRule' || type === 'image' || type === 'taskReference') {
      add(type, 'block', undefined, true)
      continue
    }
    if (type === 'hardBreak') { add(type, 'inline', undefined, true); continue }
    if (inlineNodes.has(type)) add(type, 'inline', undefined, true)
    else add(type, 'block', undefined, true)
  }
  if (!specs.doc) add('doc', null, 'block*')
  if (!specs.paragraph) add('paragraph', 'block', 'inline*')
  if (!specs.text) add('text', 'inline')
  const markSpecs = Object.fromEntries([...marks].map(([type, keys]) => [
    type,
    keys.size ? { attrs: Object.fromEntries([...keys].map((key) => [key, { default: null }])) } : {},
  ]))
  return new Schema({ nodes: specs, marks: markSpecs })
}

function emptyEditorDocument() {
  return { type: 'doc', content: [{ type: 'paragraph' }] }
}

function legacyDescriptionToContentJson(description) {
  if (typeof description !== 'string' || !description.trim()) return emptyEditorDocument()
  // Older task rows stored HTML/plain text only. Keep a conservative text
  // conversion here so the first Yjs bootstrap cannot replace that legacy
  // content with an empty paragraph. New rows always provide content_json and
  // never use this fallback.
  const text = description
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<\/(?:p|div|li|h[1-6]|blockquote|pre)>/gi, '\n')
    .replace(/<[^>]+>/g, '')
    .replace(/&nbsp;/gi, ' ')
    .replace(/&amp;/gi, '&')
    .replace(/&lt;/gi, '<')
    .replace(/&gt;/gi, '>')
    .replace(/\r\n?/g, '\n')
  const lines = text.split('\n').map((line) => line.trim()).filter(Boolean)
  return {
    type: 'doc',
    content: lines.length
      ? lines.map((line) => ({ type: 'paragraph', content: [{ type: 'text', text: line }] }))
      : [{ type: 'paragraph' }],
  }
}

function contentJsonHasText(contentJson) {
  if (!contentJson || typeof contentJson !== 'object') return false
  if (contentJson.type === 'text' && typeof contentJson.text === 'string' && contentJson.text.length > 0) return true
  // diagramBlock（流程图）与 image/taskReference 一样属于非文字正文内容
  if (contentJson.type === 'image' || contentJson.type === 'taskReference' || contentJson.type === 'diagramBlock') return true
  return Array.isArray(contentJson.content) && contentJson.content.some(contentJsonHasText)
}

function bootstrapDocument(contentJson, { title = null, metadata = null } = {}) {
  const content = contentJson && typeof contentJson === 'object' ? contentJson : emptyEditorDocument()
  const document = ProsemirrorTransformer.toYdoc(content, 'default', bootstrapSchema(content))
  const config = document.getMap('config')
  config.set('bodyInitialized', true)
  if (title) document.getText('title').insert(0, String(title))
  if (metadata) {
    const metadataMap = document.getMap('metadata')
    metadataMap.set('initialized', true)
    config.set('metadataInitialized', true)
    for (const [key, value] of Object.entries(metadata)) {
      metadataMap.set(key, value)
      // KnowledgeDetail reads the draft's base version from the document
      // config. Keep the value in one place as well as in the metadata map so
      // old and new clients cannot disagree about which published version the
      // draft was forked from.
      if (key === 'baseVersion') config.set('baseVersion', value)
    }
  }
  const update = Y.encodeStateAsUpdate(document)
  document.destroy()
  return update
}

async function loadState(documentName, requestHeaders) {
  const info = documentInfo(documentName)
  // A process can stop after the durable outbox is written but before the
  // regular ``.bin`` snapshot is replaced. Prefer that newest full Y.Doc
  // state on the next boot, otherwise a client could open the old document
  // and overwrite the SQL value that the outbox is about to recover.
  const pending = await readPendingProjection(info)
  if (pending?.state) {
    try {
      const pendingState = new Uint8Array(Buffer.from(pending.state, 'base64'))
      const probe = new Y.Doc()
      Y.applyUpdate(probe, pendingState)
      probe.destroy()
      const cookie = requestHeaders.get('cookie') ?? ''
      if (await knowledgeStateMatchesCurrentVersion(info, pendingState, cookie)) return pendingState
      return await resetKnowledgeDraftToPublished(pendingState, info, cookie)
    } catch (error) {
      console.error(`协同待处理快照无效 document=${documentName}`, error?.message ?? error)
    }
  }
  const stored = await loadStoredState(info)
  if (stored) {
    if (info.resource === 'task' && info.kind === 'body') {
      // A snapshot created by an older rollout may contain only the default
      // empty paragraph even though the SQL row still has legacy HTML in
      // ``description``. Repair that one-time migration case from SQL before
      // serving the document; an intentionally empty current task is kept.
      try {
        const storedDocument = new Y.Doc()
        Y.applyUpdate(storedDocument, stored)
        const storedContent = TiptapTransformer.fromYdoc(storedDocument, 'default')
        if (!contentJsonHasText(storedContent)) {
          const cookie = requestHeaders.get('cookie') ?? ''
          if (cookie) {
            const todo = await backendJson(`/api/tasks/${encodeURIComponent(info.taskId)}`, cookie)
            if (!contentJsonHasText(todo.contentJson) && typeof todo.description === 'string' && todo.description.trim()) {
              storedDocument.destroy()
              return bootstrapDocument(legacyDescriptionToContentJson(todo.description), {})
            }
          }
        }
        // Snapshots from before the authoritative bootstrap contract did not
        // carry this marker. Preserve their content but add the marker in the
        // state served to the client so a later deliberate clear can be
        // projected as an empty task instead of being mistaken for startup.
        if (storedDocument.getMap('config').get('bodyInitialized') !== true) {
          storedDocument.getMap('config').set('bodyInitialized', true)
          const normalizedStored = Y.encodeStateAsUpdate(storedDocument)
          storedDocument.destroy()
          return normalizedStored
        }
        storedDocument.destroy()
      } catch (error) {
        console.warn(`协同旧任务正文检查失败 document=${documentName}`, error?.message ?? error)
      }
    }
    if (info.resource !== 'knowledge') return stored
    // A review approval or an explicit administrator commit can advance the
    // published version while the draft file is still on disk. Do not reopen
    // a working document based on an older published version.
    const cookie = requestHeaders.get('cookie') ?? ''
    if (await knowledgeStateMatchesCurrentVersion(info, stored, cookie)) return stored
    // 版本过期：重置草稿为已发布内容（先删旧再插新），避免与客户端本地
    // 恢复的旧草稿叠加成双份。
    return await resetKnowledgeDraftToPublished(stored, info, cookie)
  }
  const cookie = requestHeaders.get('cookie') ?? ''
  // Direct Agent connections are authenticated and permission-checked by
  // FastAPI, then supply their SQL seed to handleAgentDocumentRequest. Avoid
  // making an unauthenticated browser API request while Hocuspocus creates
  // that direct document.
  if (!cookie) return undefined
  try {
    if (info.resource === 'task' && info.kind === 'body') {
      const todo = await backendJson(`/api/tasks/${encodeURIComponent(info.taskId)}`, cookie)
      const hasLegacyDescription = typeof todo.description === 'string' && todo.description.trim()
      const content = todo.contentJson && (contentJsonHasText(todo.contentJson) || !hasLegacyDescription)
        ? todo.contentJson
        : legacyDescriptionToContentJson(todo.description)
      return bootstrapDocument(content, {})
    }
    if (info.resource === 'note') {
      const note = await initialSeed(info, cookie)
      return bootstrapDocument(note.contentJson, { title: note.title })
    }
    if (info.resource === 'knowledge') {
      const note = await initialSeed(info, cookie)
      return bootstrapDocument(note.contentJson, {
        title: note.title,
        metadata: {
          categoryId: note.categoryId ?? null,
          tags: Array.isArray(note.tags) ? note.tags : [],
          baseVersion: note.versionNo,
        },
      })
    }
  } catch (error) {
    // A malformed legacy JSON document should not prevent the websocket from
    // opening. The editable client can use the serialized initialization claim
    // as a safe fallback, while read-only clients retain their SQL fallback.
    console.warn(`协同初始文档生成失败 document=${documentName}`, error?.message ?? error)
  }
  if (info.resource !== 'task' || info.kind === 'body') return undefined

  // Metadata needs an initial value even for read-only members. Seed the Y.Doc
  // on the trusted server so the first client never has to write permissions it
  // does not have merely to display the task metadata.
  const todo = await backendJson(`/api/tasks/${encodeURIComponent(info.taskId)}`, cookie)
  const seed = new Y.Doc()
  const title = seed.getText('title')
  if (todo.title) title.insert(0, String(todo.title))
  const metadata = seed.getMap('metadata')
  metadata.set('initialized', true)
  Object.entries(metadataFromTodo(todo)).forEach(([key, value]) => metadata.set(key, value))
  const tags = seed.getArray('tags')
  if (Array.isArray(todo.tags) && todo.tags.length > 0) tags.push(todo.tags.map((tag) => String(tag)))
  const update = Y.encodeStateAsUpdate(seed)
  seed.destroy()
  return update
}

async function persistBodyProjection({ documentName, document, lastContext, actorIds = [] }) {
  const info = documentInfo(documentName)
  if (!['body', 'note'].includes(info.kind)) return
  const fragment = document.getXmlFragment('default')
  // The config marker may arrive just before the initial setContent call. The
  // collaboration document is authoritative; an empty *uninitialized*
  // fragment must not erase the SQL projection before the first editor has
  // seeded it. Once the marker is present, an empty task body is a valid user
  // result and is projected as a normal empty ProseMirror document. Personal
  // notes follow the same rule because their title lives in this document.
  if (fragment.length === 0 && document.getMap('config').get('bodyInitialized') !== true) return

  const contentJson = fragment.length === 0
    ? emptyEditorDocument()
    : TiptapTransformer.fromYdoc(document, 'default')
  const body = JSON.stringify({
    ...(info.resource === 'task' ? {} : { title: document.getText('title').toString().trim() || '未命名笔记' }),
    contentJson,
    actorId: lastContext?.userId ?? null,
    actorIds,
  })
  const headers = {
    'content-type': 'application/json',
    'x-workfollow-collaboration-token': internalToken,
  }
  const endpoint = info.resource === 'task'
    ? `${backendUrl}/api/tasks/${encodeURIComponent(info.taskId)}/collaboration-snapshot`
    : `${backendUrl}/api/notes/${encodeURIComponent(info.noteId)}/collaboration-snapshot`
  let response = await fetch(endpoint, {
    method: 'PUT',
    headers,
    body,
  })

  if (!response.ok) throw new Error(`正文快照写回失败: ${response.status}`)
}

function readMetadata(document) {
  const map = document.getMap('metadata')
  const tags = document.getArray('tags').toArray().map((tag) => String(tag)).filter(Boolean)
  return {
    title: document.getText('title').toString(),
    dueAt: map.get('dueAt') ?? null,
    dueEndAt: map.get('dueEndAt') ?? null,
    priority: map.get('priority') ?? 'NONE',
    reminderAt: map.get('reminderAt') ?? null,
    recurrenceType: map.get('recurrenceType') ?? 'NONE',
    recurrenceConfig: map.get('recurrenceConfig') ?? null,
    tags,
  }
}

async function persistMetadataProjection({ documentName, document, lastContext, actorIds = [] }) {
  const info = documentInfo(documentName)
  if (info.kind !== 'metadata') return
  const metadata = readMetadata(document)
  const body = JSON.stringify({
    ...metadata,
    actorId: lastContext?.userId ?? null,
    actorIds,
  })
  const headers = {
    'content-type': 'application/json',
    'x-workfollow-collaboration-token': internalToken,
  }
  let response = await fetch(`${backendUrl}/api/tasks/${encodeURIComponent(info.taskId)}/collaboration-metadata`, {
    method: 'PUT',
    headers,
    body,
  })

  if (!response.ok) throw new Error(`元数据快照写回失败: ${response.status}`)
}

const projectionChains = new Map()
const projectionRetryTimers = new Map()
const PROJECTION_RETRY_DELAYS_MS = [500, 1_000, 2_000, 5_000]

function projectionDocumentName(info) {
  if (info.resource === 'task') return info.kind === 'body' ? `task:${info.taskId}` : `task-meta:${info.taskId}`
  return info.resource === 'note' ? `note:${info.noteId}` : `knowledge-draft:${info.noteId}`
}

function enqueueProjection(info, operation) {
  const key = statePath(info)
  const previous = projectionChains.get(key) ?? Promise.resolve()
  const current = previous.catch(() => undefined).then(operation)
  projectionChains.set(key, current)
  void current.catch(() => undefined).finally(() => {
    if (projectionChains.get(key) === current) projectionChains.delete(key)
  })
  return current
}

async function projectSnapshot(info, data, state, actorIds, projectionId) {
  // Hocuspocus may call onStoreDocument again while this projection waits on
  // FastAPI. ``data.document`` is a live Y.Doc and can advance before the
  // queued operation runs; projecting that live object while persisting the
  // older encoded state would make SQL and the durable snapshot disagree.
  // Rehydrate both from the same immutable update instead.
  const snapshotDocument = new Y.Doc()
  try {
    Y.applyUpdate(snapshotDocument, state)
    const projectionData = { ...data, document: snapshotDocument, actorIds }
    if (info.kind === 'metadata') await persistMetadataProjection(projectionData)
    else await persistBodyProjection(projectionData)
    await storeState(info, state)
    await clearPendingProjection(info, projectionId)
  } finally {
    snapshotDocument.destroy()
  }
}

async function projectSnapshotWithRetry(info, data, state, actorIds, projectionId, attempts = PROJECTION_RETRY_DELAYS_MS.length + 1) {
  let lastError
  for (let attempt = 0; attempt < attempts; attempt += 1) {
    try {
      await projectSnapshot(info, data, state, actorIds, projectionId)
      return true
    } catch (error) {
      lastError = error
      if (attempt < attempts - 1) {
        await new Promise((resolve) => setTimeout(resolve, PROJECTION_RETRY_DELAYS_MS[Math.min(attempt, PROJECTION_RETRY_DELAYS_MS.length - 1)]))
      }
    }
  }
  console.error(`协同投影失败，已保留待处理快照 document=${projectionDocumentName(info)} projection=${projectionId}`, lastError?.message ?? lastError)
  return false
}

function schedulePendingProjectionRetry(info, delayMs = Math.max(...PROJECTION_RETRY_DELAYS_MS) * 2) {
  const key = statePath(info)
  if (projectionRetryTimers.has(key)) return
  const timer = setTimeout(() => {
    projectionRetryTimers.delete(key)
    void enqueueProjection(info, async () => {
      const record = await readPendingProjection(info)
      if (!record) return
      const state = new Uint8Array(Buffer.from(record.state, 'base64'))
      const document = new Y.Doc()
      try {
        Y.applyUpdate(document, state)
        const data = {
          documentName: record.documentName,
          document,
          lastContext: record.lastContext ?? null,
        }
        const ok = await projectSnapshotWithRetry(
          info,
          data,
          state,
          Array.isArray(record.actorIds) ? record.actorIds : [],
          record.projectionId,
        )
        if (!ok) schedulePendingProjectionRetry(info)
      } finally {
        document.destroy()
      }
    })
  }, delayMs)
  projectionRetryTimers.set(key, timer)
}

async function replayPendingProjections() {
  const files = await readdir(dataDir)
  for (const filename of files.filter((item) => item.endsWith('.pending'))) {
    try {
      const raw = JSON.parse(await readFile(path.join(dataDir, filename), 'utf8'))
      if (typeof raw?.documentName !== 'string') continue
      const info = documentInfo(raw.documentName)
      schedulePendingProjectionRetry(info, 0)
    } catch (error) {
      console.error(`读取协同待处理快照失败 file=${filename}`, error?.message ?? error)
    }
  }
}

let server
server = new Server({
  port,
  address,
  quiet: true,
  debounce: 500,
  maxDebounce: 10_000,
  async onAuthenticate({ documentName, requestHeaders, connectionConfig }) {
    return authorize(documentName, requestHeaders, connectionConfig)
  },
  async onLoadDocument({ documentName, requestHeaders }) {
    return loadState(documentName, requestHeaders)
  },
  onChange({ documentName, context, document }) {
    rememberActor(documentName, context)
    if (document) markInitializationClaims(documentName, document)
  },
  async onStoreDocument(data) {
    const info = documentInfo(data.documentName)
    if (['body', 'note'].includes(info.kind) && data.document.getXmlFragment('default').length === 0) {
      // The editor writes its initialization marker before seeding the
      // ProseMirror fragment. Do not persist that transient empty document or
      // a later client could mistake it for an initialized blank resource.
      // Once the marker exists, an intentionally empty body is a valid result
      // for both tasks and notes; the durable marker tells those cases apart
      // without relying on a timing guess. Knowledge drafts are the
      // exception: they always fall back to the published version, so a
      // marker-only snapshot would poison the draft into a permanent blank
      // page — never persist one.
      const initialized = data.document.getMap('config').get('bodyInitialized') === true
      if (!initialized || info.resource === 'knowledge') {
        pendingActors.delete(data.documentName)
        return
      }
    }
    const state = Y.encodeStateAsUpdate(data.document)
    rememberActor(data.documentName, data.lastContext)
    // FastAPI deliberately bounds actor_ids so one long-lived document cannot
    // grow an unbounded audit payload. Keep the newest actors: the last
    // context is sent separately and the backend also adds actor_id as a
    // notification fallback when needed.
    const actorIds = [...(pendingActors.get(data.documentName) ?? [])].slice(-20)
    pendingActors.delete(data.documentName)
    const projectionId = randomUUID()
    const pendingRecord = {
      projectionId,
      documentName: data.documentName,
      state: Buffer.from(state).toString('base64'),
      actorIds,
      lastContext: data.lastContext ? {
        userId: data.lastContext.userId ?? null,
        userName: data.lastContext.userName ?? null,
      } : null,
    }
    try {
      // The pending file is a small durable outbox. If FastAPI or SQLite is
      // temporarily unavailable, the merged Y.Doc can be projected again
      // after the process restarts instead of being discarded by Hocuspocus.
      await writePendingProjection(info, pendingRecord)
    } catch (error) {
      console.error(`写入协同待处理快照失败 document=${data.documentName}`, error?.message ?? error)
    }

    const projectionData = { ...data, actorIds }
    const ok = await enqueueProjection(
      info,
      () => projectSnapshotWithRetry(info, projectionData, state, actorIds, projectionId),
    )
    if (!ok) schedulePendingProjectionRetry(info)
  },
  onRequest({ request, response, instance }) {
    return new Promise((resolve, reject) => {
      const pathname = new URL(request.url ?? '/', 'http://workfollow.local').pathname
      if (pathname === '/health') {
        response.writeHead(200, { 'content-type': 'application/json', 'cache-control': 'no-store' })
        response.end(JSON.stringify({ status: 'ok' }))
        reject()
        return
      }
      if (pathname === '/initialize' || pathname === '/collaboration/initialize') {
        void handleInitializationRequest({ request, response, instance })
          .catch((error) => {
            if (!response.headersSent) {
              writeCorsHeaders(request, response)
              response.writeHead(error?.message === '未登录' ? 401 : 400, { 'content-type': 'application/json' })
              response.end(JSON.stringify({ detail: error?.message || '协同初始化失败' }))
            }
          })
          .finally(() => reject())
        return
      }
      if (pathname === '/internal/agent-document') {
        void handleAgentDocumentRequest({ request, response, instance })
          .catch((error) => {
            if (!response.headersSent) {
              response.writeHead(400, { 'content-type': 'application/json' })
              response.end(JSON.stringify({ detail: error?.message || 'Agent 协同操作失败' }))
            }
          })
          .finally(() => reject())
        return
      }
      resolve()
    })
  },
})

let stopping = false
async function shutdown() {
  if (stopping) return
  stopping = true
  await server.destroy()
  process.exit(0)
}

process.once('SIGINT', shutdown)
process.once('SIGTERM', shutdown)

await replayPendingProjections()
await server.listen()
console.log(`WorkFollow collaboration listening on ws://${address}:${port}`)
