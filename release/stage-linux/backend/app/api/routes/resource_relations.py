from fastapi import APIRouter, Response, status

from app.core.dependencies import CurrentUser, DbSession
from app.models.resource_relation import ResourceRelation
from app.schemas.resource_relation import ResourceRelationCreate, ResourceRelationRead
from app.services import resource_relation_service


router = APIRouter(prefix="/resource-relations", tags=["resource-relations"])


@router.post("", response_model=ResourceRelationRead, status_code=status.HTTP_201_CREATED)
def post_relation(
    payload: ResourceRelationCreate, db: DbSession, user: CurrentUser
) -> ResourceRelationRead:
    return resource_relation_service.create_relation(db, payload, user.id)


@router.delete("/{relation_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_relation(relation_id: str, db: DbSession, user: CurrentUser) -> Response:
    relation = db.get(ResourceRelation, relation_id)
    if relation is None or relation.deleted_at is not None:
        return Response(status_code=status.HTTP_204_NO_CONTENT)
    resource_relation_service.require_resource_access(
        db, relation.source_type, relation.source_id, user.id, edit=True
    )
    relation.deleted_at = resource_relation_service.local_now()
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)
