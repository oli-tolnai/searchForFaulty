const NOTIFICATION_TRIGGERS = ['checkAuctionWatches', 'checkNewListingAlerts'];
const NOTIFICATION_ZONE = 'Europe/Budapest';

function notificationPrice(value) {
  return typeof value === 'number' && Number.isFinite(value) && value >= 0;
}

function watchOperation(op, secrets, now) {
  const row = stateIdentity(op);
  if (op.type === 'watch_remove') return { ...row, deleted: true };
  const lead = op.lead_minutes === undefined ? 120 : op.lead_minutes;
  if (!notificationPrice(op.threshold) || !Number.isSafeInteger(lead) || lead < 1 || lead > 1440) invalidState();
  Object.assign(row, { threshold: op.threshold, lead_minutes: lead });
  if (op.type === 'watch_update') return row;
  const listing = favoriteListing(op.listing, secrets);
  if (rowKey(listing) !== rowKey(row) || !listing.buying_options.includes('AUCTION') ||
      !listing.end_time || listing.status !== 'ACTIVE') invalidState();
  const bid = listing.currency === 'EUR' ? listing.current_bid : null;
  return {
    ...row, title: listing.title, url: listing.url, end_time: listing.end_time, created_at: now,
    last_bid: bid, last_checked_at: listing.last_checked_at,
    status: Date.parse(listing.end_time) <= Date.parse(now) ? 'ended' : 'active', deleted: false,
  };
}

function alertOperation(op, secrets) {
  if (typeof op.id !== 'string' || !/^[a-z0-9_-]{12,80}$/i.test(op.id) ||
      redactText(op.id, secrets) !== op.id) invalidState();
  if (op.type === 'alert_remove') return { id: op.id, deleted: true };
  if (!Array.isArray(op.models) || op.models.length > FILTER_MODELS.length ||
      op.models.some(model => !FILTER_MODELS.includes(model)) || !notificationPrice(op.max_total_price) ||
      typeof op.include_unknown_shipping !== 'boolean' || typeof op.enabled !== 'boolean') invalidState();
  return {
    id: op.id, models: [...new Set(op.models)], max_total_price: op.max_total_price,
    include_unknown_shipping: op.include_unknown_shipping, enabled: op.enabled, deleted: false,
  };
}

function publishNotification(title, message, priority, tags, click) {
  const topic = PropertiesService.getScriptProperties().getProperty('NTFY_TOPIC')?.trim();
  if (!topic || !/^[a-zA-Z0-9_-]{1,64}$/.test(topic)) {
    throw new AppError('ntfy_not_configured', 'Az értesítési csatornát az Apps Script beállításaiban kell megadni.');
  }
  const safeTitle = redactText(title, [topic]);
  const headers = { Title: '=?UTF-8?B?' + Utilities.base64Encode(safeTitle, Utilities.Charset.UTF_8) + '?=',
    Priority: priority, Tags: tags };
  if (click && redactText(click, [topic]) === click &&
      /^https:\/\/(?:[a-z0-9-]+\.)*ebay\.[a-z.]+\/[^\s]*$/i.test(click)) headers.Click = click;
  const payload = redactText(message, [topic]);
  try {
    const response = UrlFetchApp.fetch('https://ntfy.sh/' + topic, {
      method: 'post', contentType: 'text/plain; charset=utf-8', payload, headers,
      muteHttpExceptions: true, followRedirects: false,
    });
    const status = response.getResponseCode();
    if (status >= 200 && status < 300) return;
  } catch {
    // Fetch errors can contain the full topic URL.
  }
  throw new AppError('ntfy_failed', 'Az értesítés küldése sikertelen.');
}

function installTriggers() {
  setNotificationTriggers(true);
}

function removeTriggers() {
  setNotificationTriggers(false);
}

function setNotificationTriggers(install) {
  const lock = LockService.getScriptLock();
  if (!lock.tryLock(10000)) throw new AppError('state_busy', 'A szinkron foglalt, próbáld újra.');
  try {
    const triggers = ScriptApp.getProjectTriggers();
    for (const name of NOTIFICATION_TRIGGERS) {
      const existing = triggers.filter(trigger => trigger.getHandlerFunction() === name &&
        trigger.getEventType() === ScriptApp.EventType.CLOCK);
      for (const trigger of existing.slice(install ? 1 : 0)) ScriptApp.deleteTrigger(trigger);
      if (install && !existing.length) {
        const builder = ScriptApp.newTrigger(name).timeBased();
        (name === 'checkAuctionWatches' ? builder.everyMinutes(10) : builder.everyHours(2)).create();
      }
    }
  } finally {
    lock.releaseLock();
  }
}

function runNotifications(name, action) {
  // A lease lasts longer than Apps Script's execution limit. Network requests run without a Sheets lock.
  const props = PropertiesService.getScriptProperties();
  const key = 'notification_lease_' + name;
  const expiry = String(Date.now() + 7 * 60000);
  const lock = LockService.getScriptLock();
  if (!lock.tryLock(10000)) return;
  try {
    if (Number(props.getProperty(key)) > Date.now()) return;
    props.setProperty(key, expiry);
  } finally {
    lock.releaseLock();
  }
  try {
    action(props);
  } catch {
    Logger.log(name === 'watches' ? 'Az aukciófigyelés futása sikertelen.' : 'Az időzített keresés sikertelen.');
  } finally {
    if (lock.tryLock(10000)) {
      try {
        if (props.getProperty(key) === expiry) props.deleteProperty(key);
      } finally {
        lock.releaseLock();
      }
    }
  }
}

function notificationSecrets(props) {
  return [props.getProperty('NTFY_TOPIC')?.trim(), ...(props.getProperty('CLIENT_TOKENS') || '')
    .split(',').map(value => value.trim()), props.getProperty('EBAY_CLIENT_ID')?.trim(),
  props.getProperty('EBAY_CLIENT_SECRET')?.trim()].filter(Boolean);
}

function watchIsDue(watch, now) {
  const remaining = Date.parse(watch.end_time) - now.getTime();
  return watch.status === 'active' && !watch.notified_at && remaining > 0 &&
    remaining <= watch.lead_minutes * 60000 && watch.last_bid != null &&
    Number(watch.last_bid) < watch.threshold &&
    Utilities.formatDate(now, NOTIFICATION_ZONE, 'yyyy-MM-dd') ===
    Utilities.formatDate(new Date(watch.end_time), NOTIFICATION_ZONE, 'yyyy-MM-dd');
}

function watchResult(watch, response, now, secrets) {
  if (!response) return null;
  const checked = { last_checked_at: now.toISOString() };
  if (response.getResponseCode() === 404) return { ...checked, status: 'ended' };
  const data = responseObject(response);
  if (data.warnings !== undefined) {
    Logger.log('eBay getItem: ' + JSON.stringify(safeWarning(data.warnings, [...secrets, ...sellerIdentities(data.seller)])));
  }
  const end = timestamp(data.itemEndDate);
  if (response.getResponseCode() !== 200 || data.itemId !== watch.source_listing_id) return null;
  if (unavailable(data) || (end && Date.parse(end) <= now.getTime())) {
    return { ...checked, status: 'ended', end_time: end || watch.end_time };
  }
  if (!end || !Array.isArray(data.buyingOptions) || !data.buyingOptions.includes('AUCTION')) return null;
  const [bid, currency] = money(data.currentBidPrice);
  return { ...checked, end_time: end, last_bid: currency === 'EUR' ? bid : null };
}

function saveWatchChecks(updates) {
  return withStateLock(book => {
    const meta = readState(book);
    const rows = new Map(readRows(book, 'watches').map(row => [rowKey(row), row]));
    const watches = [];
    for (const { watch, change } of updates) {
      const row = rows.get(rowKey(watch));
      if (!row || (row.revision !== watch.revision && !change.notified_at)) continue;
      const safeChange = change.notified_at
        ? { notified_at: change.notified_at, status: row.deleted || row.status === 'ended' ? row.status : 'notified' }
        : change;
      watches.push({ ...row, ...safeChange, revision: ++meta.revision });
    }
    if (watches.length) commitStateWrite(book, meta, { watches });
    return watches;
  });
}

function sendDueWatches(watches) {
  for (const watch of watches) {
    const now = new Date();
    if (!watchIsDue(watch, now)) continue;
    const time = Utilities.formatDate(new Date(watch.end_time), NOTIFICATION_ZONE, 'HH:mm');
    try {
      publishNotification('Aukció zárul', 'Ma ' + time + '-kor zárul: ' +
        notificationTitle(watch.title) + ' – ' + watch.last_bid + ' € (határ: ' + watch.threshold + ' €)',
      'high', 'alarm_clock', watch.url);
      saveWatchChecks([{ watch, change: { notified_at: now.toISOString() } }]);
    } catch (error) {
      if (!(error instanceof AppError) || !error.code.startsWith('ntfy_')) throw error;
      Logger.log('Az aukció értesítését nem sikerült elküldeni.');
    }
  }
}

function checkAuctionWatches() {
  runNotifications('watches', props => {
    const watches = withStateLock(book => {
      readState(book);
      return readRows(book, 'watches').filter(row => !row.deleted && ['active', 'notified'].includes(row.status));
    });
    const now = new Date();
    const expired = watches.filter(row => Date.parse(row.end_time) <= now.getTime());
    for (let offset = 0; offset < expired.length; offset += 20) {
      saveWatchChecks(expired.slice(offset, offset + 20).map(watch => ({ watch, change: { status: 'ended' } })));
    }
    const active = watches.filter(row => row.status === 'active' && Date.parse(row.end_time) > now.getTime());
    if (!active.length) return;

    const token = applicationToken(ebayCredentials(), dailyCounter);
    const secrets = [...notificationSecrets(props), token];
    const size = ebayFetchBatchSize();
    for (let offset = 0; offset < active.length; offset += size) {
      const batch = active.slice(offset, offset + size);
      const requests = batch.map(row => fetchOptions({
        url: EBAY_ROOT + '/buy/browse/v1/item/' + encodeURIComponent(row.source_listing_id),
        method: 'get', headers: browseHeaders(token),
      }));
      dailyCounter('browse', requests.length);
      let responses;
      try {
        responses = UrlFetchApp.fetchAll(requests);
      } catch {
        Logger.log('Az eBay aukciós lekérdezési kötege sikertelen.');
        continue;
      }
      const checkedAt = new Date();
      const updates = batch.map((watch, index) => ({
        watch, change: watchResult(watch, responses[index], checkedAt, secrets),
      })).filter(update => update.change);
      if (updates.length) sendDueWatches(saveWatchChecks(updates));
    }
  });
}

function notificationTitle(title) {
  return Array.from(title.replace(/\s+/g, ' ').trim()).slice(0, 100).join('');
}

function alertMatches(item, rule) {
  if (item.currency !== 'EUR') return false;
  const model = item.console_model.replace(/ (?:Disc|Digital)$/, '');
  if (rule.models.length && !rule.models.includes(model) &&
      !(item.console_model === 'PS5 Digital' && rule.models.includes('PS5 (változat nem ismert)'))) return false;
  if (item.total_price !== null) return Number(item.total_price) <= rule.max_total_price;
  const price = effectivePrice(item);
  return rule.include_unknown_shipping && item.shipping_cost === null && price !== null &&
    Number(price) <= rule.max_total_price;
}

function checkNewListingAlerts() {
  runNotifications('alerts', props => {
    if (dailyCounter().daily_api_calls > 4000) {
      Logger.log('Az időzített keresés kimaradt: a napi eBay-hívásszám 4000 fölött van.');
      return;
    }
    const enabled = withStateLock(book => {
      readState(book);
      return readRows(book, 'alerts').some(row => !row.deleted && row.enabled);
    });
    if (!enabled) return;
    const result = searchEbay(EU_COUNTRIES, QUERIES, notificationSecrets(props));
    if (result.status === 'error') return;
    const matches = withStateLock(book => {
      readState(book);
      const rules = readRows(book, 'alerts').filter(row => !row.deleted && row.enabled);
      const hidden = new Set(readRows(book, 'hidden').filter(row => !row.deleted).map(rowKey));
      const notified = new Set(readRows(book, 'notified').map(rowKey));
      return [...result.listings, ...result.unknown_shipping].filter(item =>
        item.status === 'ACTIVE' && ['console', 'console_bundle', 'needs_review'].includes(item.item_type) &&
        item.ships_to_hu !== 'no' && !hidden.has(rowKey(item)) && !notified.has(rowKey(item)) &&
        rules.some(rule => alertMatches(item, rule)));
    });
    if (!matches.length) return;
    const lines = matches.slice(0, 5).map(item => '• ' + notificationTitle(item.title) +
      (item.total_price === null ? ' – szállítási díj nem ismert' : ' – ' + item.total_price + ' €'));
    const message = matches.length + ' új találat megfelel az értesítési szabályoknak.\n' + lines.join('\n');
    publishNotification('Új konzolajánlat', message,
      'default', 'video_game', matches.length === 1 ? matches[0].url : null);
    withStateLock(book => {
      const rows = readRows(book, 'notified');
      const notifiedAt = new Date().toISOString();
      for (const item of matches) {
        rows.push({ source: item.source, source_listing_id: item.source_listing_id, notified_at: notifiedAt });
      }
      writeRows(book, 'notified', rows);
      SpreadsheetApp.flush();
    });
  });
}
