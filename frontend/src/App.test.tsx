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
    possibly_not_faulty: false, listed_at: null,
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

  it('az ár- és típusszűrőket azonnal alkalmazza új keresés nélkül', async () => {
    await search(response({
      listings: [item({
        title: 'Ismert díj', price: '50', shipping_cost: '30', shipping_currency: 'EUR', total_price: '80',
      })],
      unknown_shipping: [
        item({ source_listing_id: 'auction', title: 'Ismeretlen díjú aukció', buying_options: ['AUCTION'],
          price: null, current_bid: '40', end_time: '2099-11-15T12:00:00Z' }),
        item({ source_listing_id: 'board', title: 'Külön alaplap', item_type: 'mainboard', price: '20' }),
      ],
    }))
    expect(screen.getByText('2 / 3 találat')).toBeInTheDocument()
    fireEvent.change(screen.getByLabelText('Hirdetéstípus'), { target: { value: 'fixed' } })
    expect(screen.queryByText('Ismeretlen díjú aukció')).not.toBeInTheDocument()
    fireEvent.change(screen.getByLabelText('Hirdetéstípus'), { target: { value: 'both' } })
    fireEvent.change(screen.getByLabelText(/Max\. vételár/), { target: { value: '45' } })
    expect(screen.queryByText('Ismert díj')).not.toBeInTheDocument()
    expect(screen.getByText('Ismeretlen díjú aukció')).toBeInTheDocument()
    fireEvent.change(screen.getByLabelText(/Max\. vételár/), { target: { value: '' } })
    fireEvent.change(screen.getByLabelText(/Max\. teljes ár/), { target: { value: '60' } })
    expect(screen.queryByText('Ismert díj')).not.toBeInTheDocument()
    expect(screen.getByText('Ismeretlen díjú aukció')).toBeInTheDocument()
    fireEvent.click(screen.getByRole('switch', { name: 'Alaplapok mutatása' }))
    expect(screen.getByText('Külön alaplap')).toBeInTheDocument()
    fireEvent.click(screen.getByLabelText('Xbox Series S'))
    expect(screen.getByText('0 / 3 találat')).toBeInTheDocument()
    expect(searchListings).toHaveBeenCalledTimes(1)
  })

  it('jelöli a korai licitet és a 24 órás szűrő megtartja a fix áras tételeket', async () => {
    vi.useFakeTimers()
    vi.setSystemTime(new Date('2026-11-13T12:00:00Z'))
    await search(response({ unknown_shipping: [
      item({ title: 'Fix áras konzol', possibly_not_faulty: true }),
      item({ source_listing_id: 'early', title: 'Korai aukció', buying_options: ['AUCTION'], end_time: '2026-11-16T12:00:00Z' }),
      item({ source_listing_id: 'soon', title: 'Közelgő aukció', buying_options: ['AUCTION'], end_time: '2026-11-14T12:00:00Z' }),
    ] }))
    expect(screen.getByText('Korai licit – a végső ár várhatóan magasabb')).toBeInTheDocument()
    expect(screen.getByText('Lehet, hogy nem hibás')).toBeInTheDocument()
    expect(screen.getByText('Fix ár', { selector: '.image-tag' })).toHaveClass('fixed-tag')
    fireEvent.change(screen.getByLabelText('Aukciók'), { target: { value: 'day' } })
    expect(screen.queryByText('Korai aukció')).not.toBeInTheDocument()
    expect(screen.getByText('Közelgő aukció')).toBeInTheDocument()
    expect(screen.getByText('Fix áras konzol')).toBeInTheDocument()
    expect(searchListings).toHaveBeenCalledTimes(1)
  })

  it('a legújabbakat rendezi előre, a dátum nélküli találatokat utoljára', async () => {
    await search(response({ unknown_shipping: [
      item({ title: 'Dátum nélkül' }),
      item({ source_listing_id: 'older', title: 'Régebbi', listed_at: '2026-11-11T12:00:00Z' }),
      item({ source_listing_id: 'newer', title: 'Újabb', listed_at: '2026-11-13T12:00:00Z' }),
    ] }))
    fireEvent.change(screen.getByLabelText('Rendezés'), { target: { value: 'newest' } })
    expect(screen.getAllByRole('heading', { level: 3 }).map((heading) => heading.textContent)).toEqual([
      'Újabb', 'Régebbi', 'Dátum nélkül',
    ])
  })
})
