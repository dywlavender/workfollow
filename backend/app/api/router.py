from fastapi import APIRouter

from app.api.routes import admin, attachments, audit, auth, folders, health, note_shares, note_templates, notes, notifications, quick_links, resource_relations, team_notes, team_tasks, teams, todos


api_router = APIRouter()
api_router.include_router(health.router)
api_router.include_router(auth.router)
api_router.include_router(admin.router)
api_router.include_router(teams.router)
api_router.include_router(team_tasks.router)
api_router.include_router(team_notes.router)
api_router.include_router(todos.router, prefix="/tasks")
# Keep the original path during the client migration; both paths operate on
# the same Task table and permission service.
api_router.include_router(todos.router, prefix="/todos", include_in_schema=False)
api_router.include_router(quick_links.router)
api_router.include_router(folders.router)
api_router.include_router(note_templates.router)
api_router.include_router(notes.router)
api_router.include_router(resource_relations.router)
api_router.include_router(note_shares.router)
api_router.include_router(notifications.router)
api_router.include_router(audit.router)
api_router.include_router(attachments.router)
