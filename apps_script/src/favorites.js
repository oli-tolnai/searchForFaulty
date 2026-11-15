function favoriteStatus(row, response, now, secrets) {
  const status = response?.getResponseCode();
  const data = response ? responseObject(response) : {};
  const checkedAt = now.toISOString();
  if (data.warnings !== undefined) {
    Logger.log('eBay getItem: ' + JSON.stringify(safeWarning(data.warnings, [...secrets, ...sellerIdentities(data.seller)])));
  }
  if (status === 404) return { status: 'ENDED', last_checked_at: checkedAt, last_check_error: null, last_check_error_at: null };
  const options = data.buyingOptions;
  const end = timestamp(data.itemEndDate);
  const auction = Array.isArray(options) && options.includes('AUCTION');
  if (status !== 200 || data.itemId !== row.source_listing_id ||
      (!unavailable(data) && !(end && Date.parse(end) <= now.getTime()) &&
        (!Array.isArray(options) || (auction ? !end : !options.includes('FIXED_PRICE'))))) {
    return { status: 'UNKNOWN', last_check_error: status && status !== 200 ? 'eBay HTTP ' + status
      : 'A hirdetés állapota nem ellenőrizhető.', last_check_error_at: checkedAt };
  }
  const [price, currency] = money(auction ? data.currentBidPrice : data.price);
  return {
    status: unavailable(data) || (end && Date.parse(end) <= now.getTime()) ? 'ENDED' : 'ACTIVE',
    end_time: end, price: auction ? null : price, current_bid: auction ? price : null, currency,
    buying_options: Array.isArray(options) ? options.filter(value => typeof value === 'string') : row.buying_options,
    bid_count: auction && Number.isSafeInteger(data.bidCount) && data.bidCount >= 0 ? data.bidCount : null,
    last_checked_at: checkedAt, last_check_error: null, last_check_error_at: null,
  };
}

function refreshFavorites(params, clientSecrets) {
  requireKeys(params, []);
  const now = new Date();
  const rows = withStateLock(book => {
    readState(book);
    return readRows(book, 'favorites').filter(row => !row.deleted && row.status !== 'ENDED')
      .sort((a, b) => String(a.last_check_error_at || a.last_checked_at || '')
        .localeCompare(String(b.last_check_error_at || b.last_checked_at || ''))).slice(0, 30);
  });
  let calls = 0;
  const countCall = (kind, count) => {
    dailyCounter(kind, count);
    calls += count;
  };
  const updates = new Map();
  if (rows.length) {
    const batchSize = ebayFetchBatchSize();
    let token;
    let credentials;
    try {
      credentials = ebayCredentials();
      token = applicationToken(credentials, countCall);
    } catch (error) {
      if (!(error instanceof AppError)) throw error;
    }
    const secrets = token ? [...clientSecrets, token, credentials.clientId, credentials.secret] : clientSecrets;
    for (let offset = 0; offset < rows.length; offset += batchSize) {
      const batch = rows.slice(offset, offset + batchSize);
      let responses = [];
      if (token) {
        try {
          countCall('browse', batch.length);
          responses = UrlFetchApp.fetchAll(batch.map(row => fetchOptions({
            url: EBAY_ROOT + '/buy/browse/v1/item/' + encodeURIComponent(row.source_listing_id),
            method: 'get', headers: browseHeaders(token),
          })));
        } catch {
          // Unavailable rows retain their last successful check time.
        }
      }
      batch.forEach((row, index) => updates.set(rowKey(row), favoriteStatus(row, responses[index], now, secrets)));
    }
  }
  const revision = withStateLock(book => {
    const meta = readState(book);
    const previous = new Map(rows.map(row => [rowKey(row), row.revision]));
    const favorites = readRows(book, 'favorites').filter(row =>
      updates.has(rowKey(row)) && previous.get(rowKey(row)) === row.revision)
      .map(row => ({ ...row, ...updates.get(rowKey(row)), revision: ++meta.revision }));
    if (favorites.length) commitStateWrite(book, meta, { favorites });
    return meta.revision;
  });
  return { revision, api_calls: calls, ...dailyCounter() };
}
