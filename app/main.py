"""Small release-observable API."""

import os

from fastapi import FastAPI

VERSION = os.getenv("APP_VERSION", "dev")
app = FastAPI(title="Secure Release API", version=VERSION)


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/version")
def version() -> dict[str, str]:
    return {"version": VERSION}
