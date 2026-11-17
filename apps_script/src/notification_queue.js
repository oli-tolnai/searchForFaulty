const NOTIFICATION_BATCH_LIMIT = 100;

function queueNotification(kind, title, body, url, listingIds, now, expiresAt) {
  return {
    id: Utilities.getUuid(), created_at: now.toISOString(), kind, title, body, url,
    source_listing_ids: listingIds, delivered_devices: [], expires_at: expiresAt.toISOString(),
  };
}

function queueTestNotification() {
  const now = new Date();
  const row = queueNotification('new_listings', 'Próbaértesítés',
    'Az értesítések működnek a Console Deal Finder alkalmazásban.', null, [],
    now, new Date(now.getTime() + 24 * 3600000));
  withStateLock(book => commitStateWrite(book, readState(book), { notifications: [row] }));
  forwardToNtfy(row);
  return row.id;
}

function validNotificationId(id) {
  return typeof id === 'string' && /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/.test(id);
}

function liveNotifications(book) {
  readState(book);
  const now = Date.now();
  const all = readRows(book, 'notifications');
  const rows = all.filter(row => Date.parse(row.expires_at) > now);
  if (all.length !== rows.length) {
    writeRows(book, 'notifications', rows);
    SpreadsheetApp.flush();
  }
  return rows;
}

function notificationsPull(params) {
  requireKeys(params, ['device_id']);
  if (!validNotificationId(params.device_id)) invalidState();
  return withStateLock(book => {
    const notifications = liveNotifications(book)
      .filter(row => !row.delivered_devices.includes(params.device_id))
      .slice(0, NOTIFICATION_BATCH_LIMIT)
      .map(({ delivered_devices, ...row }) => row);
    return { notifications };
  });
}

function notificationsAck(params) {
  requireKeys(params, ['device_id', 'ids']);
  if (!validNotificationId(params.device_id) || !Array.isArray(params.ids) ||
      params.ids.length > NOTIFICATION_BATCH_LIMIT || !params.ids.every(validNotificationId)) invalidState();
  const ids = new Set(params.ids);
  return withStateLock(book => {
    const rows = liveNotifications(book);
    let changed = false;
    for (const row of rows) {
      if (!ids.has(row.id) || row.delivered_devices.includes(params.device_id)) continue;
      row.delivered_devices.push(params.device_id);
      changed = true;
    }
    if (changed) {
      writeRows(book, 'notifications', rows);
      SpreadsheetApp.flush();
    }
    return { acknowledged: true };
  });
}
