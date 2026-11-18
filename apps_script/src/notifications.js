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
  return { ...alertValues(op, secrets), id: op.id, deleted: false };
}

function publishNotification(title, message, priority, tags, click) {
  const topic = PropertiesService.getScriptProperties().getProperty('NTFY_TOPIC')?.trim();
  if (!topic || !/^[a-zA-Z0-9_-]{1,64}$/.test(topic)) {
    throw new AppError('ntfy_not_configured', 'Az értesítési csatornát az Apps Script beállításaiban kell megadni.');
  }
  const safeTitle = redactText(title, [topic]);
  // X-Priority is ntfy's canonical header and avoids conflicts with HTTP Priority.
  const headers = { Title: '=?UTF-8?B?' + Utilities.base64Encode(safeTitle, Utilities.Charset.UTF_8) + '?=',
    'X-Priority': priority, Tags: tags };
  if (click && redactText(click, [topic]) === click &&
      /^https:\/\/(?:[a-z0-9-]+\.)*ebay\.[a-z.]+\/[^\s]*$/i.test(click)) headers.Click = click;
  const payload = redactText(message, [topic]);
  let response;
  try {
    response = UrlFetchApp.fetch('https://ntfy.sh/' + topic, {
      method: 'post', contentType: 'text/plain; charset=utf-8', payload, headers,
      muteHttpExceptions: true, followRedirects: false,
    });
  } catch (error) {
    // Fetch errors can contain the full topic URL.
    const exception = String(error?.message || '');
    const reason = /timed out|timeout/i.test(exception) ? 'időtúllépés' : 'az ntfy nem érhető el az Apps Scriptből';
    throw new AppError('ntfy_failed', 'Az értesítés küldése sikertelen (' + reason + ').');
  }
  const status = response.getResponseCode();
  if (status >= 200 && status < 300) return status;
  const code = responseObject(response).code;
  const provider = Number.isSafeInteger(code) && code >= 10000 && code <= 59999 ? ', ntfy ' + code : '';
  throw new AppError('ntfy_failed', 'Az értesítés küldése sikertelen (HTTP ' + status + provider + ').');
}

function forwardToNtfy(row) {
  if (PropertiesService.getScriptProperties().getProperty('NTFY_ENABLED') !== 'true') return;
  const auction = row.kind === 'auction_closing';
  try {
    publishNotification(row.title, row.body, auction ? 'high' : 'default',
      auction ? 'alarm_clock' : row.source_listing_ids.length ? 'video_game' : 'bell', row.url);
  } catch (error) {
    Logger.log(error instanceof AppError ? error.message : 'Az opcionális ntfy-küldés sikertelen.');
  }
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
  const queued = withStateLock(book => {
    const meta = readState(book);
    const rows = new Map(readRows(book, 'watches').map(row => [rowKey(row), row]));
    const watches = [];
    const notifications = [];
    const now = new Date();
    for (const { watch, change } of updates) {
      const row = rows.get(rowKey(watch));
      if (!row || row.revision !== watch.revision) continue;
      const current = { ...row, ...change, revision: ++meta.revision };
      if (watchIsDue(current, now)) {
        const end = new Date(current.end_time);
        const time = Utilities.formatDate(end, NOTIFICATION_ZONE, 'HH:mm');
        const body = 'Ma ' + time + '-kor zárul: ' + notificationTitle(current.title) +
          ' – ' + current.last_bid + ' € (határ: ' + current.threshold + ' €)';
        notifications.push(queueNotification('auction_closing', 'Aukció zárul', body,
          current.url, [current.source_listing_id], now, end));
        current.status = 'notified';
        current.notified_at = now.toISOString();
      }
      watches.push(current);
    }
    if (watches.length) commitStateWrite(book, meta, notifications.length ? { watches, notifications } : { watches });
    return notifications;
  });
  queued.forEach(forwardToNtfy);
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
      if (updates.length) saveWatchChecks(updates);
    }
  });
}

function notificationTitle(title) {
  return Array.from(title.replace(/\s+/g, ' ').trim()).slice(0, 100).join('');
}

function checkNewListingAlerts() {
  runNotifications('alerts', props => {
    ecbExchangeRate();
    if (dailyCounter().daily_api_calls > 4000) {
      Logger.log('Az időzített keresés kimaradt: a napi eBay-hívásszám 4000 fölött van.');
      return;
    }
    const groups = withStateLock(book => {
      readState(book);
      const rules = readRows(book, 'alerts').filter(row => !row.deleted && row.enabled);
      return Object.keys(DEVICE_GROUPS).filter(group => rules.some(rule =>
        alertDefaults(rule).device_groups.includes(group) && (!rule.models.length ||
        rule.models.some(model => DEVICE_GROUPS[group].models.includes(model)))));
    });
    if (!groups.length) return;
    const result = searchEbay(EU_COUNTRIES, configuredQueries(groups), notificationSecrets(props));
    if (result.status === 'error') return;
    const row = withStateLock(book => {
      const meta = readState(book);
      const rules = readRows(book, 'alerts').filter(row => !row.deleted && row.enabled);
      const hidden = new Set(readRows(book, 'hidden').filter(row => !row.deleted).map(rowKey));
      const notified = new Set(readRows(book, 'notified').map(rowKey));
      const matches = [...result.listings, ...result.unknown_shipping].filter(item =>
        item.status === 'ACTIVE' &&
        item.ships_to_hu === 'yes' && !hidden.has(rowKey(item)) && !notified.has(rowKey(item)) &&
        rules.some(rule => alertMatches(item, rule)));
      if (!matches.length) return null;
      const lines = matches.slice(0, 5).map(item => '• ' + notificationTitle(item.title) +
        (item.total_price === null ? ' – szállítási díj nem ismert' : ' – ' + item.total_price + ' €'));
      const message = matches.length + ' új találat megfelel az értesítési szabályoknak.\n' + lines.join('\n');
      const now = new Date();
      const singleEnd = matches.length === 1 && matches[0].end_time ? Date.parse(matches[0].end_time) : Infinity;
      const expiry = new Date(Math.min(now.getTime() + 6 * 3600000, singleEnd));
      const notification = queueNotification('new_listings', 'Új eBay-ajánlat', message,
        matches.length === 1 ? matches[0].url : null,
        matches.slice(0, 5).map(item => item.source_listing_id), now, expiry);
      commitStateWrite(book, meta, {
        notifications: [notification],
        notified: matches.map(item => ({
          source: item.source, source_listing_id: item.source_listing_id, notified_at: now.toISOString(),
        })),
      });
      return notification;
    });
    if (row) forwardToNtfy(row);
  });
}
