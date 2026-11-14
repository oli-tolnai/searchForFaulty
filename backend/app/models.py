from datetime import datetime
from decimal import Decimal
from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field, JsonValue

NonNegativeMoney = Annotated[Decimal, Field(ge=0, allow_inf_nan=False)]
ItemType = Literal[
    "console", "console_bundle", "mainboard", "not_console", "unsupported_model", "needs_review"
]


class Listing(BaseModel):
    source: Literal["ebay"] = "ebay"
    source_listing_id: str
    title: str
    url: str
    image_url: str | None = None
    console_model: str
    item_type: ItemType
    is_banned: bool = False
    possibly_not_faulty: bool = False
    buying_options: list[str]
    price: Decimal | None = None
    current_bid: Decimal | None = None
    bid_count: int | None = None
    currency: str | None = None
    shipping_cost: Decimal | None = None
    shipping_currency: str | None = None
    total_price: Decimal | None = None
    item_country: str | None = None
    end_time: datetime | None = None
    listed_at: datetime | None = None
    condition: str | None = None
    status: Literal["ACTIVE", "ENDED", "UNKNOWN"] = "ACTIVE"
    last_checked_at: datetime
    fault_source: Literal["condition"] = "condition"

    @property
    def effective_price(self) -> Decimal | None:
        return self.current_bid if "AUCTION" in self.buying_options else self.price


class SearchFilters(BaseModel):
    model_config = ConfigDict(extra="forbid")

    max_price: NonNegativeMoney | None = None
    max_total_price: NonNegativeMoney | None = None
    buying_options: Literal["auction", "fixed", "both"] = "both"
    console_models: list[str] = Field(default_factory=list)
    include_mainboards: bool = False


class QueryStatus(BaseModel):
    query: str
    status: Literal["success", "error"]
    error: str | None = None
    warnings: list[JsonValue] = Field(default_factory=list)
    count: int


class CountryStatus(BaseModel):
    country: str
    status: Literal["success", "partial", "error"]
    queries: list[QueryStatus]


class ShippingTypeCounts(BaseModel):
    auction: int = 0
    fixed_price: int = 0


class UnknownShippingBreakdown(BaseModel):
    by_buying_type: ShippingTypeCounts
    by_country: dict[str, ShippingTypeCounts]


class SearchResponse(BaseModel):
    status: Literal["success", "partial", "error"]
    listings: list[Listing]
    unknown_shipping: list[Listing]
    unknown_shipping_breakdown: UnknownShippingBreakdown
    countries: list[CountryStatus]
    filtered_non_eu: int
    item_type_counts: dict[ItemType, int]
    api_calls: int
    daily_api_calls: int
    daily_browse_calls: int
    quota_warning: str | None = None
    searched_at: datetime
