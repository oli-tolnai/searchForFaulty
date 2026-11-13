import type { Listing } from './api'

export type Sort = 'total' | 'ascending' | 'descending' | 'ending'
export const isAuction = (item: Listing) => item.buying_options.includes('AUCTION')
export const price = (item: Listing) => isAuction(item) ? item.current_bid : item.price
export const end = (item: Listing) => isAuction(item) && item.end_time ? Date.parse(item.end_time) : Infinity
export const isActive = (item: Listing, now: number) => item.status === 'ACTIVE' && end(item) > now

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

export function selectListings(items: Listing[], title: string, sort: Sort, now: number) {
  const query = title.trim().toLocaleLowerCase('hu')
  return items.filter((item) =>
    isActive(item, now) && item.title.toLocaleLowerCase('hu').includes(query),
  ).sort((a, b) => {
    if (sort === 'ending') {
      const left = end(a)
      const right = end(b)
      return left === right ? 0 : left < right ? -1 : 1
    }
    const left = sort === 'total' ? a.total_price : price(a)
    const right = sort === 'total' ? b.total_price : price(b)
    if (left === null) return right === null ? 0 : 1
    if (right === null) return -1
    return (sort === 'descending' ? -1 : 1) * (Number(left) - Number(right))
  })
}
