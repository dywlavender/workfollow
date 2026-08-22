from fastapi import APIRouter, Query

from app.core.dependencies import CurrentUser, DbSession
from app.schemas.search import SearchResponse, SearchScope
from app.services import search_service


router = APIRouter(tags=["search"])


@router.get("/search", response_model=SearchResponse)
def global_search(
    db: DbSession,
    user: CurrentUser,
    q: str = Query(default="", max_length=200),
    scope: SearchScope = Query(default="all"),
    team_id: str | None = Query(default=None, alias="teamId"),
    limit: int = Query(default=20, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
) -> SearchResponse:
    items, total, has_more = search_service.search(
        db, user, q, scope=scope, team_id=team_id, limit=limit, offset=offset
    )
    return SearchResponse(
        query=q.strip(),
        items=[
            {
                "source": item.source,
                "id": item.id,
                "title": item.title,
                "excerpt": item.excerpt,
                "folder_id": item.folder_id,
                "team_id": item.team_id,
                "updated_at": item.updated_at,
            }
            for item in items
        ],
        total=total,
        has_more=has_more,
    )
