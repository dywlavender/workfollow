import asyncio
import sys
from pathlib import Path

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client


def test_stdio_server_exposes_expected_tools() -> None:
    async def inspect_tools() -> set[str]:
        parameters = StdioServerParameters(
            command=sys.executable,
            args=["-m", "app.mcp_server"],
            cwd=Path(__file__).resolve().parents[1],
            env={"WORKFOLLOW_AGENT_TOKEN": "wf_test"},
        )
        async with stdio_client(parameters) as (read_stream, write_stream):
            async with ClientSession(read_stream, write_stream) as session:
                await session.initialize()
                response = await session.list_tools()
                return {tool.name for tool in response.tools}

    assert asyncio.run(inspect_tools()) == {
        "list_notes",
        "search_notes",
        "get_note",
        "capture_note",
        "create_note",
        "append_note",
        "replace_note",
        "list_tasks",
        "get_task",
        "create_task",
        "replace_task_body",
        "update_task_metadata",
        "set_task_completed",
    }
