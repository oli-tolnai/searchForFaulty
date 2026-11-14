import type { Listing, SearchFilters } from './api'

export type Sort = 'total' | 'ascending' | 'descending' | 'ending' | 'newest'
export type LocalFilters = SearchFilters & { endingSoon: boolean }
export const DAY = 24 * 60 * 60 * 1000
export const isAuction = (item: Listing) => item.buying_options.includes('AUCTION')
export const price = (item: Listing) => isAuction(item) ? item.current_bid : item.price
export const end = (item: Listing) => isAuction(item) && item.end_time ? Date.parse(item.end_time) : Infinity
export const isActive = (item: Listing, now: number) => item.status === 'ACTIVE' && end(item) > now
export function listedAt(item: Listing) {
  const time = item.listed_at ? Date.parse(item.listed_at) : NaN
  return Number.isFinite(time) ? time : -Infinity
}

const regions = new Intl.DisplayNames('hu', { type: 'region' })
const dateTime = new Intl.DateTimeFormat('hu-HU', { dateStyle: 'medium', timeStyle: 'short' })
export const countryName = (code: string | null) => code ? regions.of(code) ?? code : 'Nem ismert'
export const dateLabel = (value: string) => dateTime.format(new Date(value))

export function money(value: string | null, currency: string | null) {
  if (value === null || !currency) return 'Nem ismert'
  return new Intl.NumberFormat('hu-HU', { style: 'currency', currency }).format(Number(value))
}

export function countdown(ms: number) {
  const seconds = Math.ceil(ms / 1000)
  const minutes = Math.floor(seconds / 60)
  const hours = Math.floor(minutes / 60)
  const days = Math.floor(hours / 24)
  if (days) return `${days} nap ${hours % 24} óra`
  if (hours) return `${hours} óra ${minutes % 60} perc`
  return `${minutes} perc ${seconds % 60} mp`
}

function matchesFilters(item: Listing, filters: LocalFilters, now: number) {
  const auction = isAuction(item)
  if (!filters.include_mainboards && item.item_type === 'mainboard') return false
  if (filters.buying_options === 'auction' && !auction) return false
  if (filters.buying_options === 'fixed' && !item.buying_options.includes('FIXED_PRICE')) return false
  if (filters.endingSoon && auction && end(item) - now > DAY) return false
  const model = item.console_model
  const family = model === 'PS5 Digital' ? 'PS5 (változat nem ismert)' : model.replace(/ (Disc|Digital)$/, '')
  if (filters.console_models.length && !filters.console_models.some((name) => name === model || name === family)) return false
  const amount = price(item)
  if (filters.max_price && (amount === null || Number(amount) > Number(filters.max_price))) return false
  return !filters.max_total_price || item.shipping_cost === null ||
    (item.total_price !== null && Number(item.total_price) <= Number(filters.max_total_price))
}

export function selectListings(items: Listing[], title: string, sort: Sort, now: number, filters: LocalFilters) {
  const query = title.trim().toLocaleLowerCase('hu')
  return items.filter((item) =>
    isActive(item, now) && matchesFilters(item, filters, now) && item.title.toLocaleLowerCase('hu').includes(query),
  ).sort((a, b) => {
    if (sort === 'ending') {
      const left = end(a)
      const right = end(b)
      return left === right ? 0 : left < right ? -1 : 1
    }
    if (sort === 'newest') {
      const left = listedAt(a)
      const right = listedAt(b)
      return left === right ? 0 : left > right ? -1 : 1
    }
    const left = sort === 'total' ? a.total_price : price(a)
    const right = sort === 'total' ? b.total_price : price(b)
    if (left === null) return right === null ? 0 : 1
    if (right === null) return -1
    return (sort === 'descending' ? -1 : 1) * (Number(left) - Number(right))
  })
}
