import { useState } from 'react'
import type { Listing } from './api'
import { countdown, countryName, dateLabel, end, isAuction, money, price } from './listings'

const typeLabels: Partial<Record<Listing['item_type'], string>> = {
  console_bundle: 'Csomag', needs_review: 'Ellenőrzendő', mainboard: 'Alaplap',
}

function ListingImage({ src }: { src: string | null }) {
  const [failed, setFailed] = useState(false)
  if (src && /^https?:\/\//i.test(src) && !failed) {
    return <img src={src} alt="" loading="lazy" referrerPolicy="no-referrer" onError={() => setFailed(true)} />
  }
  return <div className="image-empty">
    <svg aria-hidden="true" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.4">
      <rect x="3" y="4" width="18" height="16" rx="2" /><path d="m3 16 5-5 4 4 3-3 6 6" /><circle cx="16" cy="9" r="1" />
    </svg>
    Nincs kép
  </div>
}

export function ListingCard({ item, now }: { item: Listing; now: number }) {
  const auction = isAuction(item)
  const deadline = end(item)
  const typeLabel = typeLabels[item.item_type]
  return <article className="listing">
    <div className="listing-image">
      <ListingImage key={item.image_url} src={item.image_url} />
      <span className={auction ? 'image-tag auction-tag' : 'image-tag'}>{auction ? 'Aukció' : 'Fix ár'}</span>
    </div>
    <div className="listing-body">
      <div className="listing-meta"><span>{countryName(item.item_country)}</span><span>eBay</span></div>
      <h3>{item.title}</h3>
      <div className="badges">
        <span>{item.console_model}</span>
        {typeLabel && item.console_model !== typeLabel && <span>{typeLabel}</span>}
        {item.is_banned && <span className="danger-badge">Tiltott (banned)</span>}
      </div>
      <div className="price-line">
        <div><div className="muted">{auction ? 'Aktuális licit' : 'Vételár'}</div><strong>{money(price(item), item.currency)}</strong></div>
        {auction && item.bid_count !== null && <span>{item.bid_count} licit</span>}
      </div>
      <dl className="costs">
        <div><dt>Szállítás Magyarországra</dt><dd>{money(item.shipping_cost, item.shipping_currency)}</dd></div>
        {item.shipping_cost !== null && item.total_price !== null &&
          <div><dt>Teljes ár</dt><dd>{money(item.total_price, item.currency)}</dd></div>}
      </dl>
      {auction && item.end_time && Number.isFinite(deadline) &&
        <div className="countdown">{countdown(deadline - now)} van hátra · Zárás: <time dateTime={item.end_time}>{dateLabel(item.end_time)}</time></div>}
      <div className="checked">Utoljára ellenőrizve: {dateLabel(item.last_checked_at)}</div>
      {/^https?:\/\//i.test(item.url) &&
        <a className="listing-link" href={item.url} target="_blank" rel="noopener noreferrer">Megnyitás az eBay-en <span aria-hidden="true">↗</span></a>}
    </div>
  </article>
}
