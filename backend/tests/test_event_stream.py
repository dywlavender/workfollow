import asyncio

from app.services.event_stream import EventHub, format_sse


def test_event_hub_replays_and_fanouts_events() -> None:
    async def scenario() -> None:
        hub = EventHub()
        hub.publish({"member"}, "task.changed", {"taskId": "task-1"})
        subscriber, replay = hub.subscribe("member", last_event_id=0)
        assert [item.event_id for item in replay] == [1]

        hub.publish({"member"}, "notification.count", {"count": 2})
        item = await asyncio.wait_for(subscriber.queue.get(), timeout=1)
        assert item.name == "notification.count"
        assert item.data == {"count": 2}
        assert "event: notification.count" in format_sse(item)

        hub.unsubscribe(subscriber)

    asyncio.run(scenario())
