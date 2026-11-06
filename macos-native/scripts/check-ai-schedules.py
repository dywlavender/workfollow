#!/usr/bin/env python3
"""Exercise a real Pi-created schedule in a disposable native App with fictional data."""
import argparse
import asyncio
from datetime import datetime, timedelta
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
    root = Path(tempfile.mkdtemp(prefix="workfollow-schedule-acceptance-"))
    app, storage = root / "WorkFollow Schedule Check.app", root / "data"
    shutil.copytree(source, app, symlinks=True)
    info_file = app / "Contents/Info.plist"
    info = plistlib.loads(info_file.read_bytes())
    info.update(CFBundleIdentifier=f"com.workfollow.native.schedule.acceptance.run{os.getpid()}",
                CFBundleDisplayName="WorkFollow 定时验收", WorkFollowAcceptanceStorageRoot=str(storage))
    info_file.write_bytes(plistlib.dumps(info))
    modules = storage / "modules"
    modules.mkdir(parents=True)
    (storage / "workspace.json").write_text(json.dumps({"version": 1, "tasks": [], "notes": [],
        "taskLists": ["收集箱"], "noteFolders": []}, ensure_ascii=False))
    (modules / "assistant-briefing.json").write_text('{"automaticEnabled":false}')
    (modules / "meetings.json").write_text(json.dumps({"meetings": [], "configuration": {
        "executable": "", "model": "", "minutesModel": model, "audioExtension": ""}}))
    selected = str(uuid4()).upper()
    (modules / "ai-chat.json").write_text(json.dumps({"selectedID": selected, "records": [{
        "id": selected, "updatedAt": time.time() - 978307200,
        "messages": [{"id": str(uuid4()), "role": "user", "state": "complete", "text": "保留的虚构对话"},
                     {"id": str(uuid4()), "role": "assistant", "state": "complete", "text": "虚构旧回复"}]}]}, ensure_ascii=False))
    subprocess.run(["/usr/bin/codesign", "--force", "--deep", "--sign", "-", str(app)],
                   check=True, capture_output=True)
    cli = app / "Contents/MacOS/workfollowctl"
    status, process = None, None
    report = {"data": "fictional only", "model": model, "app": str(app), "bundleID": info["CFBundleIdentifier"],
        "storage": str(storage), "passed": False, "checks": []}
    output.parent.mkdir(parents=True, exist_ok=True)

    def save():
        output.write_text(json.dumps(report, ensure_ascii=False, indent=2))

    async def command(*words):
        child = await asyncio.create_subprocess_exec(str(cli), *words, "--app", str(app), "--json",
            stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE)
        stdout, stderr = await child.communicate()
        response = json.loads(stdout)
        if child.returncode or not response.get("ok"):
            raise RuntimeError(response.get("error", {}).get("message") or stderr.decode())
        return response["data"]

    try:
        status = await command("status")
        assert Path(status["storageDirectory"]).resolve() == storage.resolve(), "CLI 未连接独立验收目录"
        print("隔离验收 App：" + str(app), flush=True)
        note = await command("note", "create", "--title", "虚构青竹验收资料", "--content", "验收口令：青竹402。仅用于虚构定时测试。")
        initial_tasks = (await command("task", "count"))["total"]
        at = (datetime.now().astimezone() + timedelta(seconds=150)).replace(microsecond=0)
        instruction = "读取标题为‘虚构青竹验收资料’的笔记，把其中的验收口令原样记入一个新笔记，标题为‘虚构青竹定时结果’。只记录这一条，不添加待办。"
        ai = app / "Contents/Resources/AIBackend"
        process = await asyncio.create_subprocess_exec(str(ai / "runtime/arm64/python/bin/python3"), "-I", "-B",
            str(ai / "backend/ai_entry.py"), "--root", str(ai), stdin=asyncio.subprocess.PIPE,
            stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.DEVNULL)
        request_id = str(uuid4())
        params = {"sessionDirectory": str(modules / "ai-conversations"), "scene": "chat", "model": model,
            "conversationID": str(uuid4()), "progressChannel": "schedule-acceptance",
            "localTime": datetime.now().astimezone().isoformat(), "timeZone": "Asia/Shanghai",
            "workfollowCLI": str(cli), "workfollowApp": str(app),
            "workfollowSkill": str(app / "Contents/Resources/Skills/workfollow-cli/SKILL.md"),
            "message": f"先读取 WorkFollow Skill。只操作环境变量指定的虚构验收 App。请创建一个单次 AI 定时任务，标题‘虚构青竹定时验收’，执行时间 {at.isoformat()}，时区 Asia/Shanghai，指令如下：{instruction} 现在只保存计划，不提前执行。"}
        process.stdin.write((json.dumps({"id": request_id, "method": "conversation.send", "params": params}, ensure_ascii=False) + "\n").encode())
        await process.stdin.drain()
        streamed = 0
        async with asyncio.timeout(135):
            while line := await process.stdout.readline():
                response = json.loads(line)
                streamed += response.get("event", {}).get("kind") == "text"
                if response.get("id") != request_id:
                    continue
                if "error" in response:
                    raise RuntimeError(response["error"]["message"])
                report["creationReply"] = response["result"]["text"]
                break
            else:
                raise RuntimeError("Pi 设置计划时后端退出")
        jobs = await command("schedule", "list")
        assert jobs["total"] == 1, jobs
        job = await command("schedule", "get", "--id", jobs["items"][0]["id"])
        assert job["repeat"] == "once" and job["enabled"] is True, job
        assert datetime.fromisoformat(job["nextRunAt"].replace("Z", "+00:00")) == at
        assert (await command("note", "list", "--query", "虚构青竹定时结果"))["total"] == 0
        report.update(at=at.isoformat(), streamed_creation_events=streamed)
        report["checks"].append("Pi 自然语言保存单次计划，没有提前执行")
        save()
        print("已完成：真实 Pi 创建计划；等待原生 App 到点执行。", flush=True)
        deadline, previous = time.monotonic() + max(0, (at - datetime.now().astimezone()).total_seconds()) + 240, None
        while time.monotonic() < deadline:
            job = await command("schedule", "get", "--id", job["id"])
            state = job.get("lastRun", {}).get("state")
            if state != previous:
                print("原生执行状态：" + str(state), flush=True)
                previous = state
            if state in {"complete", "failed", "interrupted"}:
                break
            await asyncio.sleep(2)
        assert job.get("lastRun", {}).get("state") == "complete", job
        result_list = await command("note", "list", "--query", "虚构青竹定时结果")
        assert result_list["total"] == 1, result_list
        result = await command("note", "get", "--id", result_list["items"][0]["id"])
        assert "青竹402" in result["content"], result
        assert job["enabled"] is False and job["nextRunAt"] is None
        assert (await command("task", "count"))["total"] == initial_tasks
        assert "青竹402" in (await command("note", "get", "--id", note["id"]))["content"]
        # The chat file is read only inside this disposable acceptance workspace.
        history = json.loads((modules / "ai-chat.json").read_text())
        assert history["selectedID"].upper() == selected
        record = next(item for item in history["records"] if item["id"].upper() == job["lastRun"]["conversationID"].upper())
        answer = record["messages"][-1]
        assert answer["state"] == "complete" and any(
            item.get("url") == f"workfollow://note/{result['id']}" for item in answer.get("actions", [])), answer
        assert len(history["records"]) == 2
        report["checks"] += ["App 定时器到点调用真实 Pi", "Pi 查到虚构原笔记并保存正确口令",
            "单次计划完成后停用，没有重复记录", "流式结果及原生写入回执进入历史，原选中对话保持不变"]
        report.update(passed=True, result=result["content"], reply=answer["text"], receipts=answer.get("actions", []))
        save()
        print("通过：真实 Pi 创建计划 → App 到点执行 → 查询笔记 → 保存结果 → 历史与原生回执。", flush=True)
    except BaseException as error:
        report["failure"] = str(error)
        save()
        raise
    finally:
        if process:
            process.stdin.close()
            try:
                await asyncio.wait_for(process.wait(), 4)
            except TimeoutError:
                process.terminate()
                await process.wait()
        if status:
            try:
                os.kill(int(status["processID"]), signal.SIGTERM)
            except ProcessLookupError:
                pass
        if not keep:
            shutil.rmtree(root, ignore_errors=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, required=True, help="使用当前 Debug App 的独立副本")
    parser.add_argument("--model", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--keep", action="store_true")
    args = parser.parse_args()
    asyncio.run(check(args.app.resolve(), args.model, args.output, keep=args.keep))
