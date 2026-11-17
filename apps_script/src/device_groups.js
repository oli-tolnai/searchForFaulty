const DEVICE_GROUPS = Object.freeze({
  consoles: {
    category: '139971',
    queries: ['ps5', 'xbox series'],
    models: ['PS5 (Fat)', 'PS5 Slim', 'PS5 Pro', 'PS5 (változat nem ismert)', 'Xbox Series X', 'Xbox Series S'],
  },
  controllers: {
    category: '117042',
    queries: ['ps5 controller', 'xbox series controller', 'xbox wireless controller', 'xbox elite controller'],
    models: ['DualSense', 'DualSense Edge', 'Xbox Series kontroller', 'Xbox Elite Series 2', 'Xbox kontroller (generáció nem ismert)'],
  },
});

function configuredQueries(groups) {
  return groups.flatMap(group => DEVICE_GROUPS[group].queries);
}

function configuredModels() {
  return Object.values(DEVICE_GROUPS).flatMap(group => group.models);
}

function listingModelFamily(model) {
  if (model === 'PS5 Digital') return 'PS5 (változat nem ismert)';
  return model.replace(/ (?:Disc|Digital|\(Scuf\))$/, '');
}
