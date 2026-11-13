from pathlib import Path
from typing import Literal

from pydantic import SecretStr, field_validator
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
    hu_postal_code: SecretStr | None = None
    ebay_search_queries: tuple[str, ...] = ("ps5", "xbox series")
    ebay_countries: tuple[str, ...] = tuple(sorted(EU_COUNTRIES))

    @field_validator("hu_postal_code")
    @classmethod
    def validate_postal_code(cls, value: SecretStr | None) -> SecretStr | None:
        if value is not None:
            code = value.get_secret_value().strip()
            if len(code) != 4 or not code.isascii() or not code.isdigit():
                raise ValueError("A HU_POSTAL_CODE négy számjegyből állhat.")
            return SecretStr(code)
        return None

    @field_validator("ebay_search_queries")
    @classmethod
    def validate_queries(cls, value: tuple[str, ...]) -> tuple[str, ...]:
        queries = tuple(dict.fromkeys(query.strip() for query in value))
        if not queries or any(not query or len(query) > 100 or "," in query for query in queries):
            raise ValueError("Adj meg különálló, legfeljebb 100 karakteres keresőkifejezéseket.")
        return queries

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
