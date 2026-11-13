import json
from pathlib import Path

import pytest

from app.config import Settings


@pytest.fixture
def settings():
    return Settings(_env_file=None, ebay_client_id="fixture-id", ebay_client_secret="fixture-secret")


@pytest.fixture
def payload():
    def load(name):
        path = Path(__file__).with_name("fixtures") / f"{name}.json"
        return json.loads(path.read_text(encoding="utf-8"))

    return load
