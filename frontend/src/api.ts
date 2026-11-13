export type ItemType = 'console' | 'console_bundle' | 'mainboard' | 'not_console' | 'unsupported_model' | 'needs_review'
type Json = null | boolean | number | string | Json[] | { [key: string]: Json }
type Status = 'success' | 'partial' | 'error'
type ShippingCounts = { auction: number; fixed_price: number }

export interface Listing {
  source: 'ebay'
  source_listing_id: string
  title: string
  url: string
  image_url: string | null
  console_model: string
  item_type: ItemType
  is_banned: boolean
  buying_options: string[]
  price: string | null
  current_bid: string | null
  bid_count: number | null
  currency: string | null
  shipping_cost: string | null
  shipping_currency: string | null
  total_price: string | null
  item_country: string | null
  end_time: string | null
  condition: string | null
  status: 'ACTIVE' | 'ENDED' | 'UNKNOWN'
  last_checked_at: string
  fault_source: 'condition'
}

export interface SearchFilters {
  max_price?: string
  max_total_price?: string
  buying_options: 'auction' | 'fixed' | 'both'
  console_models: string[]
  include_mainboards: boolean
}

export interface SearchResponse {
  status: Status
  listings: Listing[]
  unknown_shipping: Listing[]
  unknown_shipping_breakdown: {
    by_buying_type: ShippingCounts
    by_country: Record<string, ShippingCounts>
  }
  countries: {
    country: string
    status: Status
    queries: { query: string; status: 'success' | 'error'; error: string | null; warnings: Json[]; count: number }[]
  }[]
  filtered_non_eu: number
  item_type_counts: Record<ItemType, number>
  api_calls: number
  daily_api_calls: number
  daily_browse_calls: number
  quota_warning: string | null
  searched_at: string
}

export async function searchListings(filters: SearchFilters): Promise<SearchResponse> {
  const response = await fetch('/api/search', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(filters),
  })
  const result = await response.json() as Partial<SearchResponse> | null
  if (
    (!response.ok && response.status !== 502) ||
    !result || !['success', 'partial', 'error'].includes(result.status ?? '') ||
    !Array.isArray(result.listings) || !Array.isArray(result.unknown_shipping) ||
    !Array.isArray(result.countries)
  ) {
    throw new Error('Érvénytelen keresési válasz.')
  }
  return result as SearchResponse
}
