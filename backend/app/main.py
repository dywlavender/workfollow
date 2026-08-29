import logging
import sys
from contextlib import asynccontextmanager
from collections.abc import AsyncIterator
from pathlib import Path

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import FileResponse
from fastapi.middleware.cors import CORSMiddleware

from app.api.router import api_router
from app.core.config import get_settings
from app.db.session import SessionLocal
from app.models.agent_action import AgentActionLog
from app.services.external_notification_service import NotificationWorker
from app.services.search_index_service import repair_fts_index
from app.services.template_service import seed_builtin_templates


settings = get_settings()


def _configure_application_logging() -> None:
    """Write application logs to stderr; launch scripts persist the stream."""
    app_logger = logging.getLogger("app")
    app_logger.setLevel(logging.INFO)
    app_logger.propagate = False
    if any(getattr(handler, "_workfollow_stream_handler", False) for handler in app_logger.handlers):
        return

    stream_handler = logging.StreamHandler(sys.stderr)
    stream_handler._workfollow_stream_handler = True  # type: ignore[attr-defined]
    stream_handler.setFormatter(logging.Formatter(
        "%(asctime)s %(levelname)s %(name)s %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    ))
    app_logger.addHandler(stream_handler)


_configure_application_logging()
logger = logging.getLogger(__name__)


def _is_task_mutation(request: Request) -> bool:
    return (
        request.method in {"POST", "PUT", "PATCH", "DELETE"}
        and any(
            request.url.path == prefix or request.url.path.startswith(f"{prefix}/")
            for prefix in ("/api/tasks", "/api/todos")
        )
    )


@asynccontextmanager
async def lifespan(_: FastAPI) -> AsyncIterator[None]:
    settings.uploads_dir.mkdir(parents=True, exist_ok=True)
    settings.files_dir.mkdir(parents=True, exist_ok=True)
    with SessionLocal() as db:
        seed_builtin_templates(db)
        repair_fts_index(db)
    notification_worker = NotificationWorker(settings)
    notification_worker.start()
    try:
        yield
    finally:
        notification_worker.stop()


app = FastAPI(title=settings.app_name, version=settings.app_version, lifespan=lifespan)


def _agent_resource(path: str) -> tuple[str | None, str | None]:
    parts = [part for part in path.split("/") if part]
    if len(parts) >= 3 and parts[:2] == ["api", "agent"] and parts[2] in {"notes", "tasks"}:
        return parts[2][:-1].upper(), parts[3] if len(parts) > 3 else None
    if len(parts) >= 3 and parts[:2] == ["api", "notes"]:
        resource_id = parts[2] if parts[2] not in {"capture", "import-markdown"} else None
        return "NOTE", resource_id
    if len(parts) >= 3 and parts[:2] in (["api", "tasks"], ["api", "todos"]):
        return "TASK", parts[2]
    return "API", None


@app.middleware("http")
async def audit_agent_writes(request: Request, call_next):  # noqa: ANN001
    response = await call_next(request)
    if (
        request.method in {"POST", "PUT", "PATCH", "DELETE"}
        and getattr(request.state, "auth_method", None) == "agent"
    ):
        resource_type, resource_id = _agent_resource(request.url.path)
        try:
            with SessionLocal() as db:
                db.add(AgentActionLog(
                    user_id=getattr(request.state, "auth_user_id", None),
                    method=request.method,
                    path=request.url.path,
                    status_code=response.status_code,
                    resource_type=resource_type,
                    resource_id=resource_id,
                ))
                db.commit()
        except Exception:
            logger.exception("记录 Agent 写操作失败 path=%s", request.url.path)
    return response


@app.middleware("http")
async def log_task_http_entry(request: Request, call_next):  # noqa: ANN001
    if not _is_task_mutation(request):
        return await call_next(request)

    logger.info("【任务HTTP入口】%s %s", request.method, request.url.path)
    response = await call_next(request)
    logger.info(
        "【任务HTTP出口】%s %s status=%s",
        request.method,
        request.url.path,
        response.status_code,
    )
    return response


app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
app.include_router(api_router, prefix="/api")


# Production/offline deployments ship the pre-built Vue application in
# ``frontend/dist``. Keep API routes registered first, then serve the SPA and
# its immutable assets from the same origin so the target machine needs only
# Python (no Node.js or separate web server).
FRONTEND_DIST = Path(__file__).resolve().parents[2] / "frontend" / "dist"


@app.get("/{full_path:path}", include_in_schema=False)
def serve_frontend(full_path: str) -> FileResponse:
    if full_path == "api" or full_path.startswith("api/"):
        raise HTTPException(status_code=404, detail="Not Found")

    index_file = FRONTEND_DIST / "index.html"
    if not index_file.is_file():
        raise HTTPException(status_code=404, detail="Frontend build not found")
    index_headers = {"Cache-Control": "no-cache, must-revalidate"}

    requested_file = (FRONTEND_DIST / full_path).resolve()
    if requested_file.is_relative_to(FRONTEND_DIST.resolve()) and requested_file.is_file():
        # Vite emits content-addressed files below assets/. They can be kept
        # forever by the browser; index.html remains the deployment switch.
        headers = index_headers
        if requested_file != index_file.resolve() and requested_file.parent.name == "assets":
            headers = {"Cache-Control": "public, max-age=31536000, immutable"}
        return FileResponse(requested_file, headers=headers)
    # The SPA entry point is the one non-hashed asset. It must be revalidated
    # after a deployment, otherwise a browser can keep an old index.html and
    # continue requesting the previous hashed JS/CSS bundle indefinitely.
    return FileResponse(index_file, headers=index_headers)
