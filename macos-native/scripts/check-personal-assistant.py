#!/usr/bin/env python3
"""Exercise real Pi and the real native memory CLI in a disposable App copy."""
import argparse
import asyncio
import json
import os
from pathlib import Path
import plistlib
import shutil
import signal
import subprocess
import tempfile
import time
from uuid import uuid4


async def check(source, model, output, *, keep=False):
    root = Path(tempfile.mkdtemp(prefix="workfollow-assistant-acceptance-"))
    app, storage = root / "WorkFollow Assistant Check.app", root / "data"
    shutil.copytree(source, app, symlinks=True)
    info_file = app / "Contents/Info.plist"
    info = plistlib.loads(info_file.read_bytes())
    info.update(CFBundleIdentifier=f"com.workfollow.native.assistant.acceptance.run{os.getpid()}",
                CFBundleDisplayName="WorkFollow 助手验收", WorkFollowAcceptanceStorageRoot=str(storage))
    info_file.write_bytes(plistlib.dumps(info))
    (storage / "modules").mkdir(parents=True)
    (storage / "workspace.json").write_text(json.dumps({"version": 1, "tasks": [], "notes": [],
        "taskLists": ["收集箱"], "noteFolders": []}, ensure_ascii=False))
    (storage / "modules/assistant-briefing.json").write_text('{"automaticEnabled":false}')
    subprocess.run(["/usr/bin/codesign", "--force", "--deep", "--sign", "-", str(app)],
                   check=True, capture_output=True)
    cli = app / "Contents/MacOS/workfollowctl"

    async def command(*words):
        child = await asyncio.create_subprocess_exec(str(cli), *words, "--app", str(app), "--json",
            stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE)
        stdout, stderr = await child.communicate()
        response = json.loads(stdout)
        if child.returncode or not response.get("ok"):
            raise RuntimeError(response.get("error", {}).get("message") or stderr.decode())
        return response["data"]

    status = await command("status")
    if Path(status["storageDirectory"]).resolve() != storage.resolve():
        raise RuntimeError("CLI 未连接到独立验收目录。")
    initial_tasks = (await command("task", "count"))["total"]
    initial_notes = (await command("note", "list"))["total"]
    ai = app / "Contents/Resources/AIBackend"
    process = await asyncio.create_subprocess_exec(str(ai / "runtime/arm64/python/bin/python3"), "-I", "-B",
        str(ai / "backend/ai_entry.py"), "--root", str(ai), stdin=asyncio.subprocess.PIPE,
        stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.DEVNULL)
    results, events = [], []
    def save_report(passed=False):
        output.write_text(json.dumps({"data": "fictional only", "model": model, "app": str(app),
            "storage": str(storage), "passed": passed, "results": results,
            "initial_tasks": initial_tasks, "initial_notes": initial_notes,
            "streamed_text_events": sum(event.get("kind") == "text" for event in events)}, ensure_ascii=False, indent=2))
    params = {"sessionDirectory": str(storage / "modules/ai-conversations"), "scene": "chat", "model": model,
        "progressChannel": "assistant-check", "localTime": "2026-11-03 09:00", "timeZone": "Asia/Shanghai",
        "workfollowCLI": str(cli), "workfollowApp": str(app),
        "workfollowSkill": str(app / "Contents/Resources/Skills/workfollow-cli/SKILL.md")}

    async def request(method, data, name):
        request_id, started = str(uuid4()), time.monotonic()
        process.stdin.write((json.dumps({"id": request_id, "method": method, "params": data}, ensure_ascii=False) + "\n").encode())
        await process.stdin.drain()
        async with asyncio.timeout(605):
            while line := await process.stdout.readline():
                value = json.loads(line)
                if "event" in value:
                    events.append(value["event"])
                if value.get("id") != request_id:
                    continue
                if "error" in value:
                    raise RuntimeError(value["error"]["message"])
                result = {"case": name, "text": value["result"]["text"], "seconds": round(time.monotonic() - started, 2)}
                results.append(result)
                save_report()
                print("已完成：" + name, flush=True)
                return result["text"]
        raise RuntimeError("助手验收后端已退出。")

    async def ask(message, name, conversation=None):
        memories = await command("memory", "list")
        return await request("conversation.send", {**params, "conversationID": conversation or str(uuid4()),
            "memories": [{"id": item["id"], "content": item["content"]} for item in memories],
            "message": "只使用环境变量指定的隔离验收 App，全部是虚构资料。" + message}, name)

    try:
        await ask("先读取 WorkFollow Skill。记住我的长期偏好：虚构工作法松竹，会议默认提前十二分钟提醒。直接保存这条偏好，不新建待办或笔记。", "remember")
        memories = await command("memory", "list")
        assert len(memories) == 1, memories
        original_id = memories[0]["id"]
        recalled = await ask("这是一个全新对话。我的会议默认提前多久提醒？只回答已保存的偏好，不修改任何数据。", "recall_in_new_conversation")
        assert "12" in recalled or "十二" in recalled, recalled
        await ask("将虚构工作法松竹的会议提醒偏好改为提前二十分钟，更新已有条目，不另加重复偏好。先读取最新版本再保存。", "update")
        memories = await command("memory", "list")
        assert len(memories) == 1 and memories[0]["id"] == original_id, memories
        assert "20" in memories[0]["content"] or "二十" in memories[0]["content"], memories
        task = await command("task", "add", "--title", "虚构松竹评审会", "--date", "2026-11-03T15:00:00+08:00", "--priority", "high")
        # Compare stored records, rather than the add command's undo receipt.
        task = await command("task", "get", "--id", task["id"])
        facts = {"localTime": "2026-11-03 09:00", "timeZone": "Asia/Shanghai", "todayCount": 1,
            "overdueCount": 0, "deadlineCount": 0, "importantCount": 1, "tasks": [{
                "id": task["id"], "title": task["title"], "list": task["list"], "url": task["url"],
                "date": task["date"], "hasTime": True, "priority": "high", "categories": ["today", "important"]}]}
        briefing = await request("assistant.briefing", {"model": model, "facts": facts,
            "memories": [{"content": memories[0]["content"]}], "progressChannel": "assistant-check"}, "daily_briefing")
        assert "松竹" in briefing and ("15" in briefing or "三点" in briefing), briefing
        assert (await command("task", "get", "--id", task["id"])) == task, "简报改变了实际任务"
        await ask("忘记虚构工作法松竹的会议提前提醒偏好，读取最新 id 和版本后删除。只删除这条偏好，不修改待办。", "forget")
        assert await command("memory", "list") == []
        await ask("这是另一个全新对话。当前有效的助手记忆里还有会议提前提醒偏好吗？只根据当前有效快照回答，未设置时请明确说明。", "after_forgetting")
        assert (await command("task", "count"))["total"] == initial_tasks + 1
        assert (await command("note", "list"))["total"] == initial_notes
        save_report(passed=True)
        print("通过：真实 Pi 保存偏好、新会话回忆、更新、只读简报和忘记；已核对原生 CLI 数据。", flush=True)
    finally:
        process.stdin.close()
        try:
            await asyncio.wait_for(process.wait(), 4)
        except TimeoutError:
            process.terminate()
            await process.wait()
        try:
            os.kill(int(status["processID"]), signal.SIGTERM)
        except ProcessLookupError:
            pass
        if not keep:
            shutil.rmtree(root, ignore_errors=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, required=True, help="当前 Debug App，验收使用它的独立副本")
    parser.add_argument("--model", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--keep", action="store_true", help="保留隔离验收 App 和虚构数据以便排查")
    args = parser.parse_args()
    asyncio.run(check(args.app.resolve(), args.model, args.output, keep=args.keep))
