import asyncio
from collections.abc import AsyncIterator
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException
from openai import APIError

from app.core.dependencies import CurrentSettings, CurrentUser
from app.schemas.ai import (
    AIChatRequest, AIChatResponse, AIConfigurationRead,
    AIGenerateRequest, AIGenerateResponse,
)
from app.services.ai_service import AIServiceError, TextAIService, configuration_read, provider_failure


router = APIRouter(prefix="/ai", tags=["ai"])


async def get_text_ai_service(settings: CurrentSettings) -> AsyncIterator[TextAIService]:
    service = TextAIService(settings)
    try:
        yield service
    finally:
        await service.close()


AIService = Annotated[TextAIService, Depends(get_text_ai_service)]


@router.get("/config", response_model=AIConfigurationRead)
def get_ai_config(settings: CurrentSettings, user: CurrentUser) -> AIConfigurationRead:
    return configuration_read(settings)


@router.post("/generate", response_model=AIGenerateResponse)
async def generate_text(payload: AIGenerateRequest, user: CurrentUser, service: AIService) -> AIGenerateResponse:
    try:
        async with asyncio.timeout(service.settings.ai_timeout_seconds):
            return await service.generate(payload)
    except AIServiceError as exc:
        raise HTTPException(status_code=exc.status_code, detail=str(exc)) from exc
    except (APIError, TimeoutError) as exc:
        failure = provider_failure(exc)
        raise HTTPException(status_code=failure.status_code, detail=str(failure)) from exc


@router.post("/chat", response_model=AIChatResponse)
async def chat(payload: AIChatRequest, user: CurrentUser, service: AIService) -> AIChatResponse:
    try:
        async with asyncio.timeout(service.settings.ai_timeout_seconds):
            return await service.chat(payload)
    except AIServiceError as exc:
        raise HTTPException(status_code=exc.status_code, detail=str(exc)) from exc
    except (APIError, TimeoutError) as exc:
        failure = provider_failure(exc)
        raise HTTPException(status_code=failure.status_code, detail=str(failure)) from exc
