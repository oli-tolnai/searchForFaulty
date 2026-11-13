from fastapi import APIRouter, Request, Response

from app.models import SearchFilters, SearchResponse

router = APIRouter()


@router.post("/api/search", response_model=SearchResponse)
def search(
    request: Request, response: Response, filters: SearchFilters | None = None
) -> SearchResponse:
    result = request.app.state.search_service.search(filters or SearchFilters())
    if result.status == "error":
        response.status_code = 502
    return result
