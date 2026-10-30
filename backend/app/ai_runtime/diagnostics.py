"""Inspect local prerequisites without sending a model prompt or changing settings."""
import asyncio

from app.ai_runtime.node_runtime import resolve_node


async def configuration_check(pi, data):
    checks = []

    async def version(executable):
        process = await asyncio.create_subprocess_exec(str(executable), "--version",
            stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.DEVNULL)
        try:
            output, _ = await asyncio.wait_for(process.communicate(), 5)
            if process.returncode != 0:
                raise RuntimeError("程序未能正常返回版本，请检查安装。")
            return output.decode(errors="replace").strip().splitlines()[0] if output else "已找到"
        finally:
            if process.returncode is None:
                process.terminate()
                await process.wait()

    try:
        node = resolve_node().executable
        checks.append({"name": "Node.js", "ok": True, "message": await version(node)})
    except Exception as exc:
        checks.append({"name": "Node.js", "ok": False, "message": str(exc)})
    try:
        command, _ = pi.command(data)
        checks.append({"name": "Pi", "ok": True, "message": await version(command[0])})
    except Exception as exc:
        checks.append({"name": "Pi", "ok": False, "message": str(exc)})
        return {"checks": checks}
    try:
        models = await pi.models(data)
        selected = data.get("model", "")
        found = not selected or any(selected in (m["id"], m["provider"] + "/" + m["id"]) for m in models)
        checks.append({"name": "模型配置", "ok": bool(models) and found,
                       "message": f"已读取 {len(models)} 个模型" if found else "所选 Pi 模型不在可用列表中"})
    except Exception as exc:
        checks.append({"name": "模型配置", "ok": False, "message": str(exc)})
    session = None
    try:
        session = await pi.session({**data, "appTools": True})
        result = await session.request({"type": "get_commands", "id": "workfollow-skill-check"}, "commands", 20)
        names = [item["name"].removeprefix("skill:") for item in result.get("commands", []) if item.get("source") == "skill"]
        checks.append({"name": "Skill", "ok": "workfollow-cli" in names, "message": "、".join(names) or "未发现 Skill"})
    except Exception as exc:
        checks.append({"name": "Skill", "ok": False, "message": str(exc)})
    finally:
        if session:
            await session.close()
    return {"checks": checks}
