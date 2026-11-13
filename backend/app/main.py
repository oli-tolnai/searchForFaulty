from contextlib import asynccontextmanager

import httpx
from fastapi import FastAPI

from app.adapters.ebay import EbayAdapter
from app.api.search import router
from app.config import Settings
from app.services.search import SearchService


def create_app(settings: Settings | None = None) -> FastAPI:
    @asynccontextmanager
    async def lifespan(app: FastAPI):
        with httpx.Client(timeout=15.0) as client:
            service = SearchService(EbayAdapter(client, settings or Settings()))
            app.state.search_service = service
            try:
                yield
            finally:
                service.close()

    app = FastAPI(
        title="Console Deal Finder",
        openapi_url=None,
        docs_url=None,
        redoc_url=None,
        lifespan=lifespan,
    )
    app.include_router(router)
    app.get("/api/health")(health)
    return app

def health() -> dict[str, str]:
    return {"status": "ok"}


app = create_app()
