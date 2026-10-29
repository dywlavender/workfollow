#!/usr/bin/env python3
"""Live Pi + bundled Skill + native CLI check in a dedicated acceptance App."""
import argparse
import asyncio
import json
import os
from pathlib import Path
import plistlib
import signal
import time
from uuid import uuid4


async def check(app, model, output):
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    storage = info.get("WorkFollowAcceptanceStorageRoot")
    if not storage or ".acceptance." not in info.get("CFBundleIdentifier", ""):
        raise RuntimeError("真实模型写入测试只允许使用独立数据目录的验收 App。")
    storage = Path(storage).resolve()
    cli = app / "Contents/MacOS/workfollowctl"

    async def command(*arguments):
        process = await asyncio.create_subprocess_exec(str(cli), *arguments, "--app", str(app), "--json",
            stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE)
        stdout, stderr = await process.communicate()
        value = json.loads(stdout)
        if process.returncode or not value.get("ok"):
            raise RuntimeError(value.get("error", {}).get("message") or stderr.decode())
        return value["data"]

    status = await command("status")
    if Path(status["storageDirectory"]).resolve() != storage:
        raise RuntimeError("CLI 未连接到验收目录，测试已停止。")
    name = "AI接入验收1029"
    lists = await command("task", "lists")
    if name in lists:
        raise RuntimeError("请使用全新的验收工作区。")
    await command("list", "create", "--name", name)
    source = await command("note", "create", "--title", "Skill验收松竹101", "--content",
        "虚构项目松竹101：核对报价，安排在2026年10月30日15:00，重要性高。仅供独立验收。")
    root = app / "Contents/Resources/AIBackend"
    process = await asyncio.create_subprocess_exec(str(root / "runtime/arm64/python/bin/python3"), "-I", "-B",
        str(root / "backend/ai_entry.py"), "--root", str(root), stdin=asyncio.subprocess.PIPE,
        stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.DEVNULL)
    conversation_id = str(uuid4())
    events, results = [], []
    params = {"conversationID": conversation_id, "sessionDirectory": str(storage / "modules/ai-conversations"),
        "scene": "chat", "model": model, "progressChannel": "check", "localTime": "2026-10-29 09:00",
        "timeZone": "Asia/Shanghai", "workfollowCLI": str(cli), "workfollowApp": str(app),
        "workfollowSkill": str(app / "Contents/Resources/Skills/workfollow-cli/SKILL.md")}

    async def ask(message):
        request_id = str(uuid4()); started = time.monotonic()
        process.stdin.write((json.dumps({"id": request_id, "method": "conversation.send", "params": {
            **params, "message": message}}, ensure_ascii=False) + "\n").encode())
        await process.stdin.drain()
        async with asyncio.timeout(605):
            while line := await process.stdout.readline():
                value = json.loads(line)
                if "event" in value: events.append(value["event"])
                if value.get("id") != request_id: continue
                if "error" in value: raise RuntimeError(value["error"]["message"])
                result = {"question": message, "text": value["result"]["text"],
                          "seconds": round(time.monotonic() - started, 2)}
                results.append(result); print("完成一轮真实 Pi 调用。", flush=True)
                return result
        raise RuntimeError("验收后端已退出。")

    try:
        await ask("仅操作环境变量 WORKFOLLOW_CLI、WORKFOLLOW_APP 指定的验收 App。先读取 Skill，再查找标题为“Skill验收松竹101”的测试笔记并读取正文。"
            "根据这份虚构资料，在清单“AI接入验收1029”新建待办“核对松竹101报价”，安排在2026年10月30日15:00，重要性高。"
            "同时新建笔记“Skill验收执行记录”，内容说明根据该测试笔记建立了这个待办。请直接保存并提供链接，不查询其他笔记或任务。")
        items = (await command("task", "list", "--list", name))["items"]
        assert len(items) == 1 and items[0]["priority"] == "high" and items[0]["date"] == "2026-10-30T07:00:00Z", items
        await ask("仍只操作刚才的验收 App。把刚才新建的“核对松竹101报价”改到2026年10月31日16:30，重要性改为中；"
            "给刚才新建的“Skill验收执行记录”追加一句“复核时间已调整”。先读取最新记录和版本再保存，不查询其他内容。")
        task = await command("task", "get", "--id", items[0]["id"])
        notes = (await command("note", "list", "--query", "Skill验收执行记录"))["items"]
        assert len(notes) == 1, notes
        note = await command("note", "get", "--id", notes[0]["id"])
        assert task["date"] == "2026-10-31T08:30:00Z" and task["priority"] == "medium", task
        assert "复核时间已调整" in note["content"], note
        assert (await command("note", "get", "--id", source["id"]))["content"] == source["content"]
        session = Path(params["sessionDirectory"]) / "chat" / (conversation_id + ".jsonl")
        calls = [part for line in session.read_text().splitlines() for part in json.loads(line).get("message", {}).get("content", [])
                 if isinstance(part, dict) and part.get("type") == "toolCall"]
        skill_read = any(call.get("name") == "read" and "SKILL.md" in call.get("arguments", {}).get("path", "") for call in calls)
        assert skill_read and any(call.get("name") == "bash" for call in calls), "Pi 未实际读取 Skill 或调用 CLI"
        output.write_text(json.dumps({"data": "fictional only", "model": model, "results": results,
            "skill_read": skill_read, "tools": [call["name"] for call in calls], "task": task,
            "note": note, "tool_status_events": sum(event.get("kind") == "status" for event in events)}, ensure_ascii=False, indent=2))
        print("通过：读取 Skill、查询笔记、新建与修改待办、新建与追加笔记；均已核对实际保存结果。")
    finally:
        process.stdin.close()
        try: await asyncio.wait_for(process.wait(), 4)
        except TimeoutError: process.terminate(); await process.wait()
        # This is the dedicated scratch App verified by status above.
        try: os.kill(int(status["processID"]), signal.SIGTERM)
        except ProcessLookupError: pass


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument("--model", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    asyncio.run(check(args.app.resolve(), args.model, args.output))
