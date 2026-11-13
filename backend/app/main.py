from fastapi import FastAPI

app = FastAPI(
    title="Console Deal Finder",
    openapi_url=None,
    docs_url=None,
    redoc_url=None,
)


@app.get("/api/health")
def health() -> dict[str, str]:
    return {"status": "ok"}
