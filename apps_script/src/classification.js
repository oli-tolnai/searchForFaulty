const UNSUPPORTED_MODELS = {
  PS1: /\b(?:ps\s*1|psx|ps\s*one|playstation\s*(?:1|one))\b/,
  PS2: /\b(?:ps\s*2|playstation\s*2)\b/,
  PS3: /\b(?:ps\s*3|playstation\s*3|cech[-\s]?[a-z0-9]+)\b/,
  PS4: /\b(?:ps\s*4|playstation\s*4|cuh[-\s]?\d{4}[a-z]?)\b/,
  PSP: /\b(?:psp|playstation\s+portable)\b/,
  'PS Vita': /\b(?:ps|playstation)\s*vita\b/,
  'Xbox One': /\bxbox\s+one\b/,
  'Xbox 360': /\bxbox\s+360\b/,
  'Xbox Classic': /\b(?:xbox\s+(?:classic|original)|(?:classic|original)\s+xbox|xbox\s+(?:konsole\s+)?erste\s+serie)\b/,
  'Nintendo Switch': /\b(?:nintendo\s+switch|switch(?:\s+(?:lite|oled|2))?)\b/,
  'Nintendo Wii': /\b(?:nintendo\s+)?wii(?:\s+u)?\b/,
  'Nintendo DS': /\b(?:nintendo\s+ds|(?:2ds|3ds))\b/,
};

function classifyItem(value) {
  const title = value.toLowerCase();
  const banned = /\b(?:banned|gebannt|gesperrt)\b/.test(title);
  const codes = [...title.matchAll(/\bcfi[-\s]?(10|11|12|20|70)\d{2}([ab])?\b/g)];
  const ps5 = codes.length > 0 || /\b(?:ps\s*5|play\s*station\s*5)\b/.test(title);
  const xbox = new Set([...title.matchAll(/\bseries\s+([xs])\b/g)].map(match => match[1]));
  const unsupported = Object.keys(UNSUPPORTED_MODELS).filter(model => UNSUPPORTED_MODELS[model].test(title));
  const consoleWord = /\b(?:spielkonsole|wohnkonsole|heimkonsole|konsole|console)s?n?\b/.test(title);
  const consoleFeature = /\b(?:825\s*gb|[12]\s*tb|(?:disc|disk|digital)e?\s+edition|für\s+teile|for\s+parts|nicht\s+funktionsfähig|läuft\s+nicht|bundle\s+(?:inkl\.?|including|mit|with))\b/.test(title);
  const explicit = /\b(?:nur\s+konsole|console\s+only|komplette?\s+(?:ps5\s+)?konsole|complete\s+(?:ps5\s+)?console|(?:konsole|console)\s+(?:mit|with))\b/.test(title);
  const generations = new Set(codes.map(([, prefix]) => ({20: 'Slim', 70: 'Pro'})[prefix] || 'Fat'));
  if (ps5 && /\bpro\b/.test(title)) generations.add('Pro');
  if (ps5 && /\bslim\b/.test(title)) generations.add('Slim');
  const editions = new Set(codes.filter(([, prefix, suffix]) => /^(10|11|12)$/.test(prefix) && suffix)
    .map(([, , suffix]) => suffix === 'a' ? 'Disc' : 'Digital'));
  if (/\bdigitale?\b/.test(title)) editions.add('Digital');
  if (/\b(?:disc|disk)\b/.test(title)) editions.add('Disc');

  const conflict = xbox.size > 1 || /\bseries\s+[xs]\s*[/|]\s*[xs]\b/.test(title)
    || generations.size > 1 || ((ps5 || xbox.size) && editions.size > 1)
    || (ps5 && xbox.size) || ((ps5 || xbox.size) && unsupported.length);
  let model = 'Ellenőrzendő';
  const edition = editions.size === 1 ? ' ' + [...editions][0] : '';
  if (!conflict && ps5) {
    const generation = [...generations][0];
    model = (({ Fat: 'PS5 (Fat)', Slim: 'PS5 Slim', Pro: 'PS5 Pro' })[generation]
      || 'PS5 (változat nem ismert)') + edition;
  } else if (!conflict && xbox.size) {
    model = 'Xbox Series ' + [...xbox][0].toUpperCase() + edition;
  } else if (!conflict && unsupported.length === 1) {
    model = unsupported[0];
  }

  let type = 'needs_review';
  const emptyBox = /\b(?:box|ovp|karton)\b.*\b(?:leer|empty|nur)\b|\b(?:leer\w*|empty|nur|only)\s+(?:box|ovp|karton)\b/.test(title);
  const onlyPart = /\b(?:nur|only)\s+(?:controller|kontroller|dualsense|manette|lüfter|netzteil|cover|gehäuse|hdmi[-\s]+(?:port|buchse))\b/.test(title);
  const board = /\b(?:mainboards?|motherboards?|alaplap|edm[-\s]?0\d{2})\b/.test(title);
  const donor = /\b(?:donor\s+boards?|boards?\s+only|platine)\b/.test(title);
  const service = /\b(?:liquid\s+metal|wärmeleitpaste|reinigung|reparaturservice|reparatur[-\s]+service|service|repair\s+service|reparatur)\b/.test(title);
  const part = /\b(?:controller|kontroller|dualsense|manette|gehäuse|cover|box|ovp|karton|kabel|netzteil|lüfter|laufwerk|drive|lemezmeghajtó|hdmi[-\s]+(?:port|buchse))(?:s|n|e|ok)?(?![\p{L}\p{N}_])/u.test(title);
  const strong = consoleWord || consoleFeature || codes.length || xbox.size || (ps5 && banned);
  const multiple = /\b(?:posten\s*\d+|lot|bundle of|[2-9]\d*\s*(?:x|×)\s*(?:ps5|xbox|konsole|console))\b/.test(title);
  if (emptyBox || onlyPart) type = 'not_console';
  else if ((board && !explicit) || (donor && !(consoleWord || consoleFeature || codes.length))) type = 'mainboard';
  else if ((service && !explicit) || (part && !strong)) type = 'not_console';
  else if (!conflict && unsupported.length) type = 'unsupported_model';
  else if (!conflict && multiple && (ps5 || xbox.size || strong)) type = 'console_bundle';
  else if (!conflict && (strong || generations.size) && (ps5 || xbox.size)) type = 'console';
  return { item_type: type, console_model: model, is_banned: banned };
}

function possiblyNotFaulty(title) {
  const value = title.toLowerCase();
  return /\b(?:neu|new|versiegelt|sealed|nagelneu|neuf|nuovo|nuevo)\b/.test(value)
    && !/\b(?:[a-zäöü]*defekt\w*|kaputt|bastler\w*|ersatzteil\w*|for\s+parts|faulty|broken|not\s+working|reparatur\w*|banned|gebannt|guasto|rotto|averiado|en\s+panne|pour\s+pièces)\b/.test(value);
}
