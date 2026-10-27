#!/usr/bin/env python3
"""Exercise the packaged CLI against an isolated copy of the actual App."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import shutil
import signal
import subprocess
import tempfile
import time

parser = argparse.ArgumentParser()
parser.add_argument('--app', type=Path, required=True)
parser.add_argument('--report', type=Path, required=True)
parser.add_argument('--keep', action='store_true')
args = parser.parse_args()
root = Path(tempfile.mkdtemp(prefix='workfollow-cli-acceptance-'))
app = root / 'WorkFollow.app'
data = root / 'data'
pid = None
checks = []
report = {'app': str(app), 'data': str(data), 'checks': checks}

def call(*words, ok=True):
    result = subprocess.run([str(app/'Contents/MacOS/workfollowctl'), *words,
                             '--app', str(app), '--json', '--timeout', '30'],
                            text=True, capture_output=True, timeout=40)
    response = json.loads(result.stdout)
    assert response['ok'] == ok and result.returncode == (0 if ok else 1), (words, result.returncode, response, result.stderr)
    return response.get('data') if ok else response['error']

def stop():
    global pid
    if pid is not None:
        os.kill(pid, signal.SIGTERM)
        for _ in range(100):
            try:
                os.kill(pid, 0)
            except ProcessLookupError:
                pid = None
                return
            time.sleep(0.05)
        raise RuntimeError('Isolated acceptance App did not stop')

try:
    shutil.copytree(args.app.resolve(), app, symlinks=True)
    info_path = app/'Contents/Info.plist'
    with info_path.open('rb') as file:
        info = plistlib.load(file)
    info['CFBundleIdentifier'] = f'com.workfollow.native.cli.acceptance.run{os.getpid()}'
    info['CFBundleDisplayName'] = 'WorkFollow CLI 验收'
    info['WorkFollowAcceptanceStorageRoot'] = str(data)
    with info_path.open('wb') as file:
        plistlib.dump(info, file)
    data.mkdir()
    (data/'workspace.json').write_text(json.dumps({'version': 1, 'tasks': [], 'notes': [],
        'taskLists': ['收集箱', 'CLI验收'], 'noteFolders': ['CLI验收']}, ensure_ascii=False))
    subprocess.run(['/usr/bin/codesign', '--force', '--deep', '--sign', '-', str(app)],
                   check=True, capture_output=True, text=True)
    status = call('status')
    assert status['storageDirectory'] == str(data)
    pid = status['processID']
    checks.append('cold launch and isolated storage')
    task = call('task', 'add', '--title', 'CLI 交付验收', '--priority', 'high', '--date', '2026-10-27', '--due', '2026-10-28')
    assert task['title'] == 'CLI 交付验收' and task['priority'] == 'high' and not task['completed']
    checks.append('create task with dates and priority')
    completed = call('task', 'complete', '--id', task['id'], '--version', task['version'])
    assert completed['completed']
    task = call('task', 'reopen', '--id', task['id'], '--version', completed['version'])
    assert not task['completed']
    checks.append('complete and reopen task')
    task = call('task', 'update', '--id', task['id'], '--version', task['version'], '--title', 'CLI 已更新交付')
    assert task['title'] == 'CLI 已更新交付'
    assert call('task', 'list', '--query', '已更新')['total'] == 1
    checks.append('update and search task')
    body = '第一行中文\n引号 "、$()、`文字` 保留\n末行'
    content = root/'content.txt'
    content.write_text(body)
    note = call('note', 'create', '--title', 'CLI 会议纪要', '--folder', 'CLI验收', '--content-file', str(content))
    assert note['content'] == body
    checks.append('create multiline UTF-8 note from file')
    appended = call('note', 'append', '--id', note['id'], '--version', note['version'], '--content', '补充：负责人待确认')
    assert appended['content'] == body+'\n补充：负责人待确认'
    error = call('note', 'append', '--id', note['id'], '--version', note['version'], '--content', '旧版本不应写入', ok=False)
    assert error['code'] == 'version_conflict'
    checks.append('append note and reject stale version')
    note = call('note', 'update', '--id', note['id'], '--version', appended['version'], '--title', 'CLI 最终纪要')
    assert note['content'] == appended['content']
    listing = call('note', 'list', '--query', '最终', '--limit', '1')
    assert listing['total'] == 1 and 'content' not in listing['items'][0]
    checks.append('rename note and metadata-only search')
    assert call('task', 'list')['total'] == 1
    group = call('group', 'create', '--name', 'CLI 工作组')
    assert group['lists'] == []
    project = call('list', 'create', '--name', 'CLI 项目', '--group', 'CLI 工作组')
    assert project['group'] == 'CLI 工作组'
    section = call('section', 'create', '--list', 'CLI 项目', '--title', '待处理')
    task = call('task', 'update', '--id', task['id'], '--version', task['version'],
                '--list', 'CLI 项目', '--section', section['id'])
    assert task['sectionID'] == section['id'] and task['group'] == 'CLI 工作组'
    assert call('task', 'list', '--section', section['id'])['total'] == 1
    checks.append('create sidebar group, list and task section and assign task')
    call('list', 'rename', '--name', 'CLI 项目', '--to', 'CLI 交付项目')
    assert call('section', 'get', '--id', section['id'])['list'] == 'CLI 交付项目'
    call('group', 'rename', '--name', 'CLI 工作组', '--to', 'CLI 公司组')
    assert call('list', 'get', '--name', 'CLI 交付项目')['group'] == 'CLI 公司组'
    call('section', 'rename', '--id', section['id'], '--title', '待交付')
    assert call('task', 'get', '--id', task['id'])['sectionTitle'] == '待交付'
    checks.append('rename list and both levels of group without losing membership')
    call('list', 'create', '--name', 'CLI 第二项目')
    call('section', 'move', '--id', section['id'], '--list', 'CLI 第二项目')
    assert call('task', 'get', '--id', task['id'])['list'] == 'CLI 第二项目'
    call('list', 'move', '--name', 'CLI 第二项目', '--group', 'CLI 公司组')
    call('list', 'move', '--name', 'CLI 第二项目', '--clear-group')
    assert call('list', 'get', '--name', 'CLI 第二项目')['group'] is None
    call('list', 'move', '--name', 'CLI 第二项目', '--group', 'CLI 公司组')
    checks.append('move section with task and move list into and out of sidebar group')
    assert call('list', 'archive', '--name', 'CLI 第二项目')['archived']
    assert call('list', 'list', '--archived', 'true')['total'] == 1
    assert 'CLI 第二项目' not in call('task', 'lists')
    assert call('task', 'add', '--title', '归档期间禁止新建', '--list', 'CLI 第二项目', ok=False)['code'] == 'invalid_argument'
    assert not call('list', 'unarchive', '--name', 'CLI 第二项目')['archived']
    checks.append('archive and restore list and reject task creation in archived list')
    stop()
    status = call('status')
    assert status['storageDirectory'] == str(data)
    pid = status['processID']
    assert call('note', 'get', '--id', note['id'])['content'] == appended['content']
    task = call('task', 'get', '--id', task['id'])
    assert task['title'] == 'CLI 已更新交付' and task['sectionID'] == section['id']
    assert task['list'] == 'CLI 第二项目' and task['group'] == 'CLI 公司组'
    assert call('section', 'list', '--list', 'CLI 第二项目')[0]['title'] == '待交付'
    assert len(call('group', 'get', '--name', 'CLI 公司组')['lists']) == 2
    checks.append('restart App and retain task, note and full organization hierarchy')
    call('group', 'dissolve', '--name', 'CLI 公司组')
    assert call('list', 'get', '--name', 'CLI 第二项目')['group'] is None
    call('section', 'delete', '--id', section['id'])
    task = call('task', 'get', '--id', task['id'])
    assert task['sectionID'] is None and task['list'] == 'CLI 第二项目'
    checks.append('dissolve groups and remove section while preserving contents')
    section = call('section', 'create', '--list', 'CLI 第二项目', '--title', '删除验收')
    call('task', 'update', '--id', task['id'], '--version', task['version'], '--section', section['id'])
    deleted = call('list', 'delete', '--name', 'CLI 第二项目')
    assert deleted['tasksMovedTo'] == '收集箱' and deleted['taskCount'] == 1
    assert call('task', 'get', '--id', task['id'])['sectionID'] is None
    call('list', 'delete', '--name', 'CLI 交付项目')
    checks.append('delete list and retain its task in inbox without orphaned section')
    stop()
    status = call('status')
    assert status['storageDirectory'] == str(data)
    pid = status['processID']
    assert call('task', 'get', '--id', task['id'])['list'] == '收集箱'
    assert call('group', 'list') == []
    assert call('list', 'list', '--query', 'CLI 第二项目')['total'] == 0
    assert call('note', 'get', '--id', note['id'])['content'] == appended['content']
    assert call('section', 'get', '--id', section['id'], ok=False)['code'] == 'not_found'
    checks.append('restart App and retain group removal and list deletion')
    report['ok'] = True
except Exception as error:
    report['ok'] = False
    report['error'] = str(error)
    raise
finally:
    try:
        stop()
    finally:
        args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n')
        if not args.keep:
            shutil.rmtree(root)
print(json.dumps(report, ensure_ascii=False))
