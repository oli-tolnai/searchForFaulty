const STATE_COLUMNS = {
  favorites: ['source', 'source_listing_id', 'saved_at', 'title', 'url', 'image_url', 'console_model',
    'item_type', 'buying_options', 'price', 'current_bid', 'currency', 'shipping_cost', 'item_country',
    'end_time', 'status', 'last_checked_at', 'last_check_error', 'revision', 'deleted', 'last_check_error_at',
    'shipping_currency', 'ships_to_hu', 'bid_count', 'is_banned', 'possibly_not_faulty', 'listed_at', 'device_group', 'is_scuf'],
  hidden: ['source', 'source_listing_id', 'hidden_at', 'title', 'revision', 'deleted'],
  seen: ['source', 'source_listing_id', 'first_seen_at'],
  settings: ['key', 'value', 'revision'],
  watches: ['source', 'source_listing_id', 'title', 'url', 'threshold', 'lead_minutes', 'created_at',
    'status', 'last_bid', 'last_checked_at', 'end_time', 'notified_at', 'revision', 'deleted'],
  alerts: ['id', 'models', 'max_total_price', 'include_unknown_shipping', 'enabled', 'revision', 'deleted'],
  notified: ['source', 'source_listing_id', 'notified_at'],
  notifications: ['id', 'created_at', 'kind', 'title', 'body', 'url',
    'source_listing_ids', 'delivered_devices', 'expires_at'],
  meta: ['key', 'value'],
};
const STATE_TABLES = ['favorites', 'hidden', 'settings', 'watches', 'alerts'];
const FILTER_FIELDS = ['models', 'device_groups', 'max_price', 'max_total', 'buying', 'ending', 'boards', 'order'];

function withStateLock(action) {
  const lock = LockService.getScriptLock();
  if (!lock.tryLock(10000)) throw new AppError('state_busy', 'A szinkron foglalt, próbáld újra.');
  try {
    return action(openStateSheet());
  } finally {
    lock.releaseLock();
  }
}

function openStateSheet() {
  const props = PropertiesService.getScriptProperties();
  let id = props.getProperty('SHEET_ID');
  let book;
  if (id) book = SpreadsheetApp.openById(id);
  else {
    book = SpreadsheetApp.create('Console Deal Finder – adatok');
    id = book.getId();
    props.setProperty('SHEET_ID', id);
    book.getSheets()[0].setName('favorites');
  }
  for (const [name, columns] of Object.entries(STATE_COLUMNS)) {
    const sheet = book.getSheetByName(name) || book.insertSheet(name);
    const available = sheet.getMaxColumns();
    if (columns.length > available) sheet.insertColumnsAfter(available, columns.length - available);
    if (!sheet.getLastRow()) sheet.getRange(1, 1, 1, columns.length).setValues([columns]);
    else if (name === 'favorites') {
      const headers = sheet.getRange(1, 1, 1, columns.length);
      if (headers.getValues()[0][columns.length - 1] !== 'is_scuf') headers.setValues([columns]);
    }
  }
  return book;
}

function initializeState() {
  withStateLock(book => {
    readState(book);
    SpreadsheetApp.flush();
  });
  Logger.log('A szinkrontáblázat készen áll.');
}

function sheetCell(value) {
  if (value == null) return '';
  if (typeof value === 'object') return JSON.stringify(value);
  // Force text, including numeric strings, and escape any leading apostrophe.
  return typeof value === 'string' ? "'" + value : value;
}

function readRows(book, table) {
  const sheet = book.getSheetByName(table);
  const columns = STATE_COLUMNS[table];
  const count = sheet.getLastRow() - 1;
  if (count < 1) return [];
  return sheet.getRange(2, 1, count, columns.length).getValues().map(cells => {
    return Object.fromEntries(columns.map((key, index) => {
      let value = cells[index];
      if (value === '') value = null;
      if (value != null && ['buying_options', 'models', 'value', 'source_listing_ids', 'delivered_devices'].includes(key)) {
        value = JSON.parse(value);
      }
      return [key, value];
    }));
  });
}

function writeRows(book, table, rows) {
  const sheet = book.getSheetByName(table);
  const columns = STATE_COLUMNS[table];
  const oldLength = sheet.getLastRow() - 1;
  if (rows.length + 1 > sheet.getMaxRows()) {
    sheet.insertRowsAfter(sheet.getMaxRows(), rows.length + 1 - sheet.getMaxRows());
  }
  if (rows.length) sheet.getRange(2, 1, rows.length, columns.length)
    .setValues(rows.map(row => columns.map(key => sheetCell(row[key]))));
  if (oldLength > rows.length) sheet.getRange(rows.length + 2, 1, oldLength - rows.length, columns.length).clearContent();
}

function rowKey(row) {
  return row.key || row.id || row.source + ':' + row.source_listing_id;
}

function readState(book) {
  const meta = Object.fromEntries(readRows(book, 'meta').map(row => [row.key, row.value]));
  const updates = meta.pending_chunks ? JSON.parse(Array.from({ length: meta.pending_chunks },
    (_, index) => meta['pending_updates_' + index].text).join('')) : meta.pending_updates;
  if (meta.pending_meta && updates) {
    // Complete a reserved batch before serving any state reads or writes.
    finishStateWrite(book, { meta: meta.pending_meta, updates });
    return meta.pending_meta;
  }
  return { revision: meta.revision || 0, op_ids: meta.op_ids || [] };
}

function finishStateWrite(book, batch) {
  for (const [table, updates] of Object.entries(batch.updates)) {
    const rows = new Map(readRows(book, table).map(row => [rowKey(row), row]));
    for (const row of updates) rows.set(rowKey(row), row);
    writeRows(book, table, Array.from(rows.values()));
  }
  SpreadsheetApp.flush();
  writeRows(book, 'meta', Object.entries(batch.meta).map(([key, value]) => ({ key, value })));
  SpreadsheetApp.flush();
}

function commitStateWrite(book, meta, updates) {
  const batch = { meta, updates };
  const encoded = JSON.stringify(updates);
  // Keep the journal within the Sheets per-cell character limit, including escaping.
  const chunks = encoded.match(/[\s\S]{1,10000}/gu);
  writeRows(book, 'meta', [{ key: 'pending_meta', value: meta },
    { key: 'pending_chunks', value: chunks.length },
    ...chunks.map((text, index) => ({ key: 'pending_updates_' + index, value: { text } }))]);
  SpreadsheetApp.flush();
  finishStateWrite(book, batch);
}

function stateGet(params) {
  requireKeys(params, ['since_revision']);
  const since = params.since_revision;
  if (!Number.isSafeInteger(since) || since < 0) invalidState();
  return withStateLock(book => {
    const meta = readState(book);
    if (since > meta.revision) invalidState();
    return { revision: meta.revision, ...Object.fromEntries(STATE_TABLES.map(table =>
      [table, readRows(book, table).filter(row => row.revision > since)])) };
  });
}

function invalidState() {
  throw new AppError('invalid_params', 'Érvénytelen szinkronművelet vagy állapot.');
}

function filterSettings(value) {
  if (!record(value)) invalidState();
  requireKeys(value, FILTER_FIELDS);
  const models = configuredModels();
  const groups = value.device_groups;
  if (!Array.isArray(value.models) || value.models.length > models.length ||
      value.models.some(model => !models.includes(model)) ||
      (groups !== undefined && (!Array.isArray(groups) || !groups.length || groups.length > Object.keys(DEVICE_GROUPS).length ||
        groups.some(group => !Object.prototype.hasOwnProperty.call(DEVICE_GROUPS, group)))) ||
      !['both', 'auction', 'fixed'].includes(value.buying) || typeof value.ending !== 'boolean' ||
      typeof value.boards !== 'boolean' || !['total', 'cheap', 'expensive', 'newest', 'ending'].includes(value.order) ||
      [value.max_price, value.max_total].some(price => price !== null &&
        (typeof price !== 'number' || !Number.isFinite(price) || price < 0))) invalidState();
  return value;
}

function stateIdentity(value) {
  if (!record(value) || value.source !== 'ebay' ||
      typeof value.source_listing_id !== 'string' || !/^v1\|\d{1,40}\|\d{1,40}$/.test(value.source_listing_id)) {
    invalidState();
  }
  return { source: value.source, source_listing_id: value.source_listing_id };
}

function favoriteListing(listing, secrets) {
  const identity = stateIdentity(listing);
  const fields = STATE_COLUMNS.favorites.filter(key => !['revision', 'deleted', 'saved_at', 'last_check_error',
    'last_check_error_at', 'source', 'source_listing_id'].includes(key));
  const safe = Object.fromEntries(fields.map(key => [key, listing[key] ?? null]));
  safe.device_group = listing.device_group === undefined ? 'consoles' : listing.device_group;
  safe.is_scuf = listing.is_scuf === undefined ? false : listing.is_scuf;
  const link = value => typeof value === 'string' && value.length <= 2048 &&
    /^https:\/\/(?:[a-z0-9-]+\.)*(?:ebay\.(?:de|com|fr|it|es|nl|at|ie|be|co\.uk)|ebayimg\.com)\//i.test(value);
  if (!link(safe.url) || (safe.image_url !== null && !link(safe.image_url)) ||
      !nonempty(safe.title) || safe.title.length > 500 || !nonempty(safe.console_model) || safe.console_model.length > 100 ||
      !ITEM_TYPES.includes(safe.item_type) || !EU_COUNTRIES.includes(safe.item_country) ||
      !Object.keys(DEVICE_GROUPS).includes(safe.device_group) || typeof safe.is_scuf !== 'boolean' ||
      !['ACTIVE', 'ENDED', 'UNKNOWN'].includes(safe.status) ||
      !['yes', 'no', 'unknown'].includes(safe.ships_to_hu) ||
      !Array.isArray(safe.buying_options) || !safe.buying_options.length ||
      safe.buying_options.some(option => !['AUCTION', 'FIXED_PRICE', 'BEST_OFFER', 'CLASSIFIED_AD'].includes(option)) ||
      !timestamp(safe.last_checked_at) ||
      (safe.end_time !== null && !timestamp(safe.end_time)) ||
      (safe.listed_at !== null && !timestamp(safe.listed_at)) ||
      [safe.price, safe.current_bid, safe.shipping_cost].some(value =>
        value !== null && (typeof value !== 'string' || value.length > 30 || !/^\d+(?:\.\d+)?$/.test(value))) ||
      [safe.currency, safe.shipping_currency].some(value => value !== null && !/^[A-Z]{3}$/.test(value)) ||
      (safe.bid_count !== null && (!Number.isSafeInteger(safe.bid_count) || safe.bid_count < 0)) ||
      typeof safe.is_banned !== 'boolean' || typeof safe.possibly_not_faulty !== 'boolean') invalidState();
  const protectedValues = [...secrets, ...sellerIdentities(listing.seller)];
  for (const key of ['title', 'url', 'image_url', 'console_model']) safe[key] = redactContact(safe[key], protectedValues);
  return { ...identity, ...safe };
}

function stateApply(params, secrets) {
  requireKeys(params, ['ops']);
  if (!Array.isArray(params.ops) || params.ops.length > 20) invalidState();
  const ops = params.ops.map(op => {
    if (!record(op) || typeof op.op_id !== 'string' || !/^[a-z0-9_-]{12,80}$/i.test(op.op_id) ||
        redactText(op.op_id, secrets) !== op.op_id) invalidState();
    const now = new Date().toISOString();
    let table;
    let row;
    switch (op.type) {
      case 'favorite_add':
        table = 'favorites';
        row = { ...favoriteListing(op.listing, secrets), saved_at: now, deleted: false };
        break;
      case 'favorite_remove':
        table = 'favorites';
        row = { ...stateIdentity(op), deleted: true };
        break;
      case 'hide':
      case 'unhide':
        table = 'hidden';
        if (op.type === 'hide' && (!nonempty(op.title) || op.title.length > 500)) invalidState();
        row = { ...stateIdentity(op), hidden_at: now,
          title: op.type === 'hide' ? redactContact(op.title, secrets) : null, deleted: op.type === 'unhide' };
        break;
      case 'setting_set':
        if (op.key !== 'filters') invalidState();
        table = 'settings';
        row = { key: op.key, value: filterSettings(op.value) };
        break;
      case 'watch_add':
      case 'watch_update':
      case 'watch_remove':
        table = 'watches';
        row = watchOperation(op, secrets, now);
        break;
      case 'alert_add':
      case 'alert_update':
      case 'alert_remove':
        table = 'alerts';
        row = alertOperation(op, secrets);
        break;
      default: invalidState();
    }
    return { id: op.op_id, type: op.type, table, row };
  });
  return withStateLock(book => {
    const meta = readState(book);
    const applied = new Set(meta.op_ids);
    const updates = {};
    const current = {};
    for (const { id, type, table, row } of ops) {
      if (applied.has(id)) continue;
      applied.add(id);
      let next = row;
      if (table === 'watches' || table === 'alerts') {
        if (!current[table]) {
          current[table] = new Map(readRows(book, table).map(existing => [rowKey(existing), existing]));
        }
        const key = rowKey(row);
        const previous = current[table].get(key);
        if (type.endsWith('_update') && (!previous || previous.deleted)) continue;
        next = { ...previous, ...row };
        if (table === 'watches') {
          if (row.deleted) next.status = 'cancelled';
          else if (previous?.notified_at) next.status = previous.status === 'ended' ? 'ended' : 'notified';
          else if (type === 'watch_add' && previous?.status === 'ended') next.status = 'ended';
        }
        current[table].set(key, next);
      }
      if (!updates[table]) updates[table] = [];
      updates[table].push({ ...next, revision: ++meta.revision });
    }
    if (applied.size !== meta.op_ids.length) {
      meta.op_ids = Array.from(applied).slice(-500);
      commitStateWrite(book, meta, updates);
    }
    return { revision: meta.revision, applied_op_ids: ops.map(op => op.id) };
  });
}

function markSearchSeen(result) {
  return withStateLock(book => {
    const all = readRows(book, 'seen');
    const now = new Date();
    const rows = all.filter(row => now.getTime() - Date.parse(row.first_seen_at) < 30 * 86400000);
    const known = new Set(rows.map(rowKey));
    const firstSync = rows.length === 0 && result.status !== 'error';
    let changed = all.length !== rows.length;
    for (const item of [...result.listings, ...result.unknown_shipping]) {
      const key = rowKey(item);
      const fresh = !known.has(key);
      item.is_new = fresh && !firstSync;
      if (fresh) {
        known.add(key);
        rows.push({ source: item.source, source_listing_id: item.source_listing_id, first_seen_at: now.toISOString() });
        changed = true;
      }
    }
    if (changed) {
      writeRows(book, 'seen', rows);
      SpreadsheetApp.flush();
    }
    return { ...result, first_sync: firstSync };
  });
}
