from pathlib import Path
from typing import Literal

from pydantic import Field, SecretStr, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

from app.geography import EU_COUNTRIES

ENV_FILE = Path(__file__).resolve().parents[2] / ".env"


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=ENV_FILE,
        env_file_encoding="utf-8-sig",
        env_ignore_empty=True,
        extra="ignore",
        hide_input_in_errors=True,
    )

    ebay_client_id: SecretStr = SecretStr("")
    ebay_client_secret: SecretStr = SecretStr("")
    ebay_env: Literal["production", "sandbox"] = "production"
    ebay_search_query: str = Field("(ps5, playstation 5, xbox series)", min_length=1, max_length=100)
    ebay_countries: tuple[str, ...] = tuple(sorted(EU_COUNTRIES))

    @field_validator("ebay_search_query", mode="before")
    @classmethod
    def strip_query(cls, value):
        return value.strip() if isinstance(value, str) else value

    @field_validator("ebay_countries")
    @classmethod
    def validate_countries(cls, countries: tuple[str, ...]) -> tuple[str, ...]:
        codes = tuple(dict.fromkeys(code.strip().upper() for code in countries))
        if not codes or any(code not in EU_COUNTRIES for code in codes):
            raise ValueError("Adj meg legalább egy érvényes EU-s országkódot.")
        return codes

    @classmethod
    def settings_customise_sources(
        cls, settings_cls, init_settings, env_settings, dotenv_settings, file_secret_settings
    ):
        return init_settings, dotenv_settings

    @property
    def ebay_api_url(self) -> str:
        if self.ebay_env == "sandbox":
            return "https://api.sandbox.ebay.com"
        return "https://api.ebay.com"
