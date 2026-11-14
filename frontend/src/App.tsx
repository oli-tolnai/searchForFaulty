import { useEffect, useMemo, useState } from 'react'
import { searchListings } from './api'
import type { Listing, SearchFilters, SearchResponse } from './api'
import { ListingCard } from './ListingCard'
import { countryName, dateLabel, end, isActive, listedAt, selectListings } from './listings'
import type { LocalFilters, Sort } from './listings'

const models = ['PS5 (Fat)', 'PS5 Slim', 'PS5 Pro', 'PS5 (változat nem ismert)', 'Xbox Series X', 'Xbox Series S']
const PAGE_SIZE = 12

function readFilters(form: HTMLFormElement): LocalFilters {
  const data = new FormData(form)
  return {
    console_models: data.getAll('models').map(String),
    max_price: String(data.get('max_price') ?? ''),
    max_total_price: String(data.get('max_total_price') ?? ''),
    buying_options: data.get('buying_options') as SearchFilters['buying_options'],
    include_mainboards: data.has('mainboards'),
    endingSoon: data.get('auction_end') === 'day',
  }
}

function SearchForm({ busy, onSearch, onFilters }: {
  busy: boolean
  onSearch: () => void
  onFilters: (filters: LocalFilters) => void
}) {
  return <form className="filter-panel" aria-label="Keresési szűrők"
    onChange={(event) => onFilters(readFilters(event.currentTarget))}
    onSubmit={(event) => { event.preventDefault(); onSearch() }}>
    <div className="panel-heading"><h2>Keresési szűrők</h2><span>eBay · Szállítás Magyarországra</span></div>
    <fieldset disabled={busy}>
      <legend>Konzolmodellek <small>· üresen hagyva mind</small></legend>
      <div className="model-options">
        {models.map((model) => <label key={model} className="model-option">
          <input type="checkbox" name="models" value={model} />{model}
        </label>)}
      </div>
      <div className="filter-grid">
        <label>Max. vételár <div className="input-unit"><input name="max_price" type="number" min="0" step="0.01" placeholder="Nincs megadva" /><span>EUR</span></div></label>
        <label>Max. teljes ár <div className="input-unit"><input name="max_total_price" type="number" min="0" step="0.01" placeholder="Nincs megadva" /><span>EUR</span></div></label>
        <label>Hirdetéstípus <select name="buying_options"><option value="both">Mind</option><option value="auction">Aukció</option><option value="fixed">Fix ár</option></select></label>
        <label>Aukciók <select name="auction_end"><option value="all">Mind</option><option value="day">24 órán belül záródók</option></select></label>
      </div>
      <div className="filter-actions">
        <label className="switch"><input type="checkbox" name="mainboards" role="switch" /> Alaplapok mutatása</label>
        <button className="primary" type="submit" disabled={busy}><SearchIcon /> Keresés indítása</button>
      </div>
    </fieldset>
  </form>
}

function SearchIcon() {
  return <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" aria-hidden="true">
    <circle cx="10.5" cy="10.5" r="6.5" /><path d="m16 16 4 4" />
  </svg>
}

function SearchStatus({ result }: { result: SearchResponse }) {
  const hasWarnings = result.countries.some((country) => country.queries.some((query) => query.warnings.length))
  return <>
    {result.status !== 'success' && <div role="alert" className="notice warning">
      {result.status === 'partial'
        ? 'Részleges keresés: egyes lekérdezések sikertelenek. A találati lista hiányos.'
        : 'A keresés sikertelen: egyik ország lekérdezése sem sikerült.'}
    </div>}
    {result.quota_warning && <div role="status" className="notice warning">{result.quota_warning}</div>}
    {(result.status !== 'success' || hasWarnings) && <details className="status-details">
      <summary>Országonkénti állapot és figyelmeztetések</summary>
      <div className="overflow-x-auto"><table>
        <thead><tr><th scope="col">Ország</th><th scope="col">Lekérdezés</th><th scope="col">Állapot</th><th scope="col">Figyelmeztetések</th></tr></thead>
        <tbody>{result.countries.flatMap(({ country, queries }) => queries.map((query) =>
          <tr key={`${country}-${query.query}`}>
            <td>{countryName(country)}</td><td>{query.query}</td>
            <td>{query.status === 'success' ? 'Sikeres' : `Hiba: ${query.error ?? 'Ismeretlen hiba'}`}</td>
            <td>{query.warnings.length ? <ul>{query.warnings.map((warning, index) =>
              <li key={index}>{typeof warning === 'string' ? warning : JSON.stringify(warning)}</li>,
            )}</ul> : 'Nincs'}</td>
          </tr>,
        ))}</tbody>
      </table></div>
    </details>}
  </>
}

function useAuctionClock(items: Listing[]) {
  const [tick, setTick] = useState(Date.now)
  useEffect(() => {
    const deadlines = items.map(end).filter(Number.isFinite)
    if (!deadlines.length) return
    let timer: ReturnType<typeof setTimeout>
    function update() {
      clearTimeout(timer)
      const now = Date.now()
      setTick(now)
      const next = Math.min(...deadlines.filter((deadline) => deadline > now))
      if (Number.isFinite(next)) timer = setTimeout(update, Math.min(1000, next - now))
    }
    update()
    document.addEventListener('visibilitychange', update)
    return () => {
      clearTimeout(timer)
      document.removeEventListener('visibilitychange', update)
    }
  }, [items])
  return Math.max(tick, Date.now())
}

function Results({ result, filters }: { result: SearchResponse; filters: LocalFilters }) {
  const [title, setTitle] = useState('')
  const [sort, setSort] = useState<Sort>('total')
  const [page, setPage] = useState(1)
  const allItems = useMemo(() => result.listings.concat(result.unknown_shipping), [result])
  const now = useAuctionClock(allItems)
  const known = selectListings(result.listings, title, sort, now, filters)
  const unknown = selectListings(result.unknown_shipping, title, sort, now, filters)
  const total = known.length + unknown.length
  const active = allItems.filter((item) => isActive(item, now))
  const hiddenBoards = active.filter((item) => item.item_type === 'mainboard').length
  const hasListingDates = allItems.some((item) => Number.isFinite(listedAt(item)))
  const counts = result.item_type_counts
  const exclusions = [
    counts.unsupported_model > 0 && `${counts.unsupported_model} nem támogatott modell (pl. PS3, PS4)`,
    counts.not_console > 0 && `${counts.not_console} nem konzol`,
    !filters.include_mainboards && hiddenBoards > 0 && `${hiddenBoards} alaplap`,
    result.filtered_non_eu > 0 && `${result.filtered_non_eu} EU-n kívüli vagy ismeretlen helyű tétel`,
  ].filter(Boolean)
  const visibleKnown = known.slice(0, page * PAGE_SIZE)
  const visibleUnknown = unknown.slice(0, Math.max(0, page * PAGE_SIZE - known.length))
  const renderCards = (items: Listing[]) => <div className="listing-grid">{items.map((item) =>
    <ListingCard key={item.source_listing_id} item={item} now={now} />,
  )}</div>

  return <section className="results" aria-label="Keresési eredmények">
    <SearchStatus result={result} />
    <div className="summary-bar">
      {result.status !== 'error' && <strong>{total} / {active.length} találat</strong>}
      <span>API-hívások: {result.api_calls} ebben a futásban · {result.daily_api_calls} ma</span>
      <span>{dateLabel(result.searched_at)}</span>
      {exclusions.length > 0 && <p>Kiszűrve: {exclusions.join(' · ')}</p>}
    </div>
    {result.status !== 'error' && <>
      <div className="results-toolbar">
        <h2>Találatok</h2>
        <label className="title-search"><SearchIcon /><input type="search" aria-label="Keresés a találatok címében" placeholder="Keresés a címekben" value={title} onChange={(event) => { setTitle(event.target.value); setPage(1) }} /></label>
        <label className="sort-label">Rendezés <select value={sort} onChange={(event) => { setSort(event.target.value as Sort); setPage(1) }}>
          <option value="total">Legalacsonyabb ismert teljes ár</option>
          <option value="ascending">Legolcsóbb</option>
          <option value="descending">Legdrágább</option>
          <option value="ending">Leghamarabb záródó aukció</option>
          {hasListingDates && <option value="newest">Legújabb hirdetések</option>}
        </select></label>
      </div>
      {total === 0 && <div className="empty">{title.trim() ? 'Nincs a címkeresésnek megfelelő találat.' : 'Nincs aktív találat a megadott szűrőkkel.'}</div>}
      {renderCards(visibleKnown)}
      {visibleUnknown.length > 0 && <section className="unknown-section">
        <h2>Ismeretlen szállítási díj – a hirdetésben ellenőrizd</h2>
        <p>{unknown.length} tételnél az eBay nem adott meg magyarországi szállítási díjat.</p>
        {renderCards(visibleUnknown)}
      </section>}
      {total > page * PAGE_SIZE && <button className="load-more" onClick={() => setPage(page + 1)}>Továbbiak betöltése · {Math.min(total, page * PAGE_SIZE)} / {total}</button>}
    </>}
  </section>
}

export default function App() {
  const [busy, setBusy] = useState(false)
  const [result, setResult] = useState<SearchResponse | null>(null)
  const [filters, setFilters] = useState<LocalFilters>({
    buying_options: 'both', console_models: [], include_mainboards: false, endingSoon: false,
  })
  const [error, setError] = useState(false)

  async function search() {
    if (busy) return
    setBusy(true)
    setError(false)
    setResult(null)
    try {
      setResult(await searchListings())
    } catch {
      setError(true)
    } finally {
      setBusy(false)
    }
  }

  return <>
    <header className="topbar"><div className="shell brand">
      <span className="brand-icon"><svg viewBox="0 0 28 28" fill="none" stroke="currentColor" strokeWidth="1.7" aria-hidden="true"><path d="M9 9h10c3 0 5 3 6 8 1 4-2 5-4 3l-3-3h-8l-3 3c-2 2-5 1-4-3 1-5 3-8 6-8Z" /><path d="M7 13h6m-3-3v6m8-3h1m2 2h1" /></svg></span>
      <span>Console Deal Finder</span>
    </div></header>
    <main className="shell">
      <div className="intro"><h1>Console Deal Finder</h1><p>Hibás konzolok az eBay-ről, közvetlen szállítással Magyarországra.</p></div>
      <SearchForm busy={busy} onSearch={search} onFilters={setFilters} />
      {busy && <div className="notice progress" role="status"><span className="spinner" aria-hidden="true" />Keresés folyamatban… ez akár fél percig is tarthat</div>}
      {error && <div className="notice warning" role="alert">A keresés nem sikerült. Ellenőrizd, hogy fut-e a backend, majd próbáld újra.</div>}
      {result && <Results result={result} filters={filters} />}
    </main>
  </>
}
