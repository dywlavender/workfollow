from __future__ import annotations

import asyncio

from fastapi import APIRouter, Header, Request
from fastapi.responses import StreamingResponse

from app.core.dependencies import CurrentUser
from app.services import event_stream


router = APIRouter(tags=["events"])


@router.get("/events", include_in_schema=False)
async def stream_events(
    request: Request,
    user: CurrentUser,
    last_event_id: str | None = Header(default=None, alias="Last-Event-ID"),
) -> StreamingResponse:
    subscriber, replay = event_stream.hub.subscribe(
        user.id,
        event_stream.parse_last_event_id(last_event_id),
    )

    async def body():
        try:
            yield "retry: 3000\n\n"
            for item in replay:
                yield event_stream.format_sse(item)
            while True:
                if await request.is_disconnected():
                    break
                try:
                    item = await asyncio.wait_for(subscriber.queue.get(), timeout=20)
                except asyncio.TimeoutError:
                    yield ": keep-alive\n\n"
                    continue
                yield event_stream.format_sse(item)
        finally:
            event_stream.hub.unsubscribe(subscriber)

    return StreamingResponse(body(), media_type="text/event-stream", headers={
        "Cache-Control": "no-cache",
        "Connection": "keep-alive",
        "X-Accel-Buffering": "no",
    })
