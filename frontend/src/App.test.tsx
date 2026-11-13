import '@testing-library/jest-dom/vitest'
import { act, cleanup, fireEvent, render, screen } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import App from './App'
import { searchListings } from './api'
import type { Listing, SearchResponse } from './api'

vi.mock('./api', () => ({ searchListings: vi.fn() }))

function item(overrides: Partial<Listing> = {}): Listing {
  return {
    source: 'ebay', source_listing_id: 'test-id', title: 'Tesztkonzol', url: 'https://example.test/item',
    image_url: null, console_model: 'PS5 Slim', item_type: 'console', is_banned: false,
    buying_options: ['FIXED_PRICE'], price: '75', current_bid: null, bid_count: null,
    currency: 'EUR', shipping_cost: null, shipping_currency: null, total_price: null,
    item_country: 'DE', end_time: null, condition: null, status: 'ACTIVE',
    last_checked_at: '2026-11-13T12:00:00Z', fault_source: 'condition', ...overrides,
  }
}

function response(overrides: Partial<SearchResponse> = {}): SearchResponse {
  return {
    status: 'success', listings: [], unknown_shipping: [],
    unknown_shipping_breakdown: { by_buying_type: { auction: 0, fixed_price: 0 }, by_country: {} },
    countries: [], filtered_non_eu: 0,
    item_type_counts: { console: 0, console_bundle: 0, mainboard: 0, not_console: 0, unsupported_model: 0, needs_review: 0 },
    api_calls: 2, daily_api_calls: 2, daily_browse_calls: 1, quota_warning: null,
    searched_at: '2026-11-13T12:00:00Z', ...overrides,
  }
}

async function search(result: SearchResponse) {
  vi.mocked(searchListings).mockResolvedValueOnce(result)
  render(<App />)
  await act(async () => fireEvent.click(screen.getByRole('button', { name: 'Keresés indítása' })))
}

afterEach(() => {
  cleanup()
  vi.useRealTimers()
  vi.resetAllMocks()
})

describe('Keresési felület', () => {
  it('az ismeretlen szállítást külön mutatja és nem ír ki teljes árat', async () => {
    await search(response({ unknown_shipping: [item()] }))
    expect(screen.getByRole('heading', { name: 'Ismeretlen szállítási díj – a hirdetésben ellenőrizd' })).toBeInTheDocument()
    expect(screen.getByText('Nem ismert')).toBeInTheDocument()
    expect(screen.queryByText('Teljes ár', { exact: true })).not.toBeInTheDocument()
  })

  it('pontosan a lejáratkor eltávolítja az aukciót', async () => {
    vi.useFakeTimers()
    vi.setSystemTime(new Date('2026-11-13T12:00:00Z'))
    await search(response({ unknown_shipping: [item({
      buying_options: ['AUCTION'], price: null, current_bid: '30',
      end_time: '2026-11-13T12:00:00.350Z',
    })] }))
    expect(screen.getByRole('heading', { name: 'Tesztkonzol' })).toBeInTheDocument()
    act(() => vi.advanceTimersByTime(349))
    expect(screen.getByRole('heading', { name: 'Tesztkonzol' })).toBeInTheDocument()
    act(() => vi.advanceTimersByTime(1))
    expect(screen.queryByRole('heading', { name: 'Tesztkonzol' })).not.toBeInTheDocument()
  })

  it('figyelmeztet a részleges futásra, és mutatja az ország hibáját', async () => {
    await search(response({ status: 'partial', countries: [{
      country: 'DE', status: 'partial', queries: [{
        query: 'ps5', status: 'error', error: 'Időtúllépés', warnings: [], count: 0,
      }],
    }] }))
    expect(screen.getByRole('alert')).toHaveTextContent('Részleges keresés')
    fireEvent.click(screen.getByText('Országonkénti állapot és figyelmeztetések'))
    expect(screen.getByText('Németország')).toBeInTheDocument()
    expect(screen.getByText('Hiba: Időtúllépés')).toBeInTheDocument()
  })

  it('teljes hibánál nem jelenít meg sikeres üres találati listát', async () => {
    await search(response({ status: 'error' }))
    expect(screen.getByRole('alert')).toHaveTextContent('A keresés sikertelen')
    expect(screen.queryByText('0 találat')).not.toBeInTheDocument()
  })
})
