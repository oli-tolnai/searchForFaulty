const DEVICE_GROUPS = Object.freeze({
  consoles: {
    category: '139971',
    queries: ['ps5', 'xbox series'],
    models: ['PS5 (Fat)', 'PS5 Slim', 'PS5 Pro', 'PS5 (változat nem ismert)', 'Xbox Series X', 'Xbox Series S'],
  },
  controllers: {
    category: '117042',
    queries: ['ps5 controller', 'xbox series controller', 'xbox wireless controller', 'xbox elite controller'],
    models: ['DualSense', 'DualSense Edge', 'Xbox Series kontroller', 'Xbox Elite Series 2',
      'Xbox Elite (sorozat nem ismert)', 'Xbox kontroller (generáció nem ismert)'],
  },
  switch: { category: '139971', queries: ['nintendo switch'], classify: classifySwitch,
    models: ['Switch V1', 'Switch V2', 'Switch Lite', 'Switch OLED', 'Switch 2', 'Switch (változat nem ismert)'] },
  steam_deck: { category: '139971', queries: ['steam deck'], classify: classifySteamDeck,
    models: ['Steam Deck LCD', 'Steam Deck OLED', 'Steam Deck (változat nem ismert)'] },
  iphone: { category: '9355', queries: [11, 12, 13, 14, 15, 16, 17].map(n => 'iphone ' + n), classify: classifyIphone,
    models: [11, 12, 13, 14, 15, 16, 17].flatMap(n => ['iPhone ' + n, 'iPhone ' + n + ' Pro', 'iPhone ' + n + ' Pro Max',
      ...([12, 13].includes(n) ? ['iPhone ' + n + ' mini'] : []), ...(n >= 14 ? ['iPhone ' + n + ' Plus'] : []),
      ...(n === 16 ? ['iPhone 16e'] : []), ...(n === 17 ? ['iPhone 17 Air'] : [])]) },
  gpu: { category: '27386', queries: ['rtx', 'radeon'], classify: classifyGpu,
    models: ['RTX 20', 'RTX 30', 'RTX 40', 'RTX 50', 'RX 5000', 'RX 6000', 'RX 7000', 'RX 9000'] },
});

function configuredQueries(groups) {
  return groups.flatMap(group => DEVICE_GROUPS[group].queries);
}

function configuredModels() {
  return Object.values(DEVICE_GROUPS).flatMap(group => group.models);
}

function listingModelFamily(model) {
  if (model === 'PS5 Digital') return 'PS5 (változat nem ismert)';
  return model.replace(/ (?:Disc|Digital|\(Scuf\)|\(Egyedi\))$/, '');
}
