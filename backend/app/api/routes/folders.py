from fastapi import APIRouter, Response, status

from app.core.dependencies import CurrentUser, DbSession
from app.schemas.note import FolderCreate, FolderRead, FolderUpdate
from app.services import note_service


router = APIRouter(prefix="/folders", tags=["folders"])


@router.get("", response_model=list[FolderRead])
def get_folders(db: DbSession, user: CurrentUser) -> list[FolderRead]:
    return note_service.list_folders(db, user.id)


@router.post("", response_model=FolderRead, status_code=status.HTTP_201_CREATED)
def post_folder(payload: FolderCreate, db: DbSession, user: CurrentUser) -> FolderRead:
    return note_service.create_folder(db, payload, user.id)


@router.put("/{folder_id}", response_model=FolderRead)
def put_folder(folder_id: str, payload: FolderUpdate, db: DbSession, user: CurrentUser) -> FolderRead:
    return note_service.update_folder(db, note_service.get_folder_or_404(db, folder_id, user.id), payload)


@router.delete("/{folder_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_folder(folder_id: str, db: DbSession, user: CurrentUser) -> Response:
    note_service.delete_folder(db, note_service.get_folder_or_404(db, folder_id, user.id))
    return Response(status_code=status.HTTP_204_NO_CONTENT)
