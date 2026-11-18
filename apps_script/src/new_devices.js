function deviceResult(type, model, banned = false, icloud = null) {
  return { item_type: type, console_model: model, is_banned: banned,
    ...(icloud === null ? {} : { icloud_status: icloud }) };
}

function deviceWords(title) {
  return diagnosticTitleWords(title).replace(/\brt\s*x\b/g, 'rtx');
}

function multipleDevices(words) {
  return /\b(?:[2-9]\d*\s*x|[2-9]\d*\s*(?:gerate|konsolen|consoles|iphones|grafikkarten)|konvolut|lot|bundle of)\b/.test(words);
}

function classifySwitch(title) {
  const words = deviceWords(title);
  const banned = /\b(?:gesperrt|gebannt|banned|softwaresperre)\b/.test(words);
  const unknown = 'Switch (változat nem ismert)';
  const result = (type, model = unknown) => deviceResult(type, model, banned);
  const full = /\b(?:heimkonsole|konsole|console|tablet|handheld)\b/.test(words);
  const part = /\b(?:leerkarton|nur (?:display|bildschirm)|mainboard|motherboard|platine|kuhler|kuhlkorper|display bildschirm|bildschirm display)\b/.test(words);
  const accessories = /\b(?:joy ?cons?|joypads?|dock|docking|ladestation|charger|netzteil|controller)\b/.test(words);
  const model = /\b(?:switch 2|bee 001)\b/.test(words) ? 'Switch 2'
    : /\b(?:oled|heg 001)\b/.test(words) ? 'Switch OLED'
    : /\b(?:lite|hdh 001)\b/.test(words) ? 'Switch Lite'
    : /\b(?:hac 001 01|had cpu 01|v2|2019)\b/.test(words) ? 'Switch V2'
    : /\b(?:hac 001|v1)\b/.test(words) ? 'Switch V1' : unknown;
  const accessoryOnly = accessories && !full && !/\b(?:switch (?:defekt|2019)|softwaresperre)\b/.test(words);
  if (part || accessoryOnly || !/\bswitch\b|\b(?:hac|heg|hdh|had|bee)\b/.test(words)) return result('not_console', model);
  if (multipleDevices(words) && !/\b[2-9] (?:defekte )?joy cons?\b/.test(words)) return result('console_bundle', model);
  return result('console', model);
}

function classifySteamDeck(title) {
  const words = deviceWords(title);
  const model = /\boled\b/.test(words) ? 'Steam Deck OLED' : /\blcd\b/.test(words) ? 'Steam Deck LCD' : 'Steam Deck (változat nem ismert)';
  const full = /\b(?:konsole|console|handheld|\d+ ?gb|\d+ ?tb)\b/.test(words);
  const part = /\b(?:leerkarton|mainboard|motherboard|nur (?:display|screen)|ersatzdisplay)\b/.test(words) ||
    (/\b(?:dock|docking|case|tasche|hulle|charger|netzteil|schutzglas|display|screen)\b/.test(words) && !full);
  return deviceResult(part ? 'not_console' : multipleDevices(words) ? 'console_bundle' : 'console', model);
}

function iphoneCloudStatus(title) {
  const words = deviceWords(title).replace(/\b(?:icload|iclod)\b/g, 'icloud');
  const free = /\b(?:icloud (?:frei|free)|fmi off|ohne icloud|no icloud lock)\b/.test(words);
  // Remove negated/free phrases before checking locks. A positive lock overrides a separate free claim.
  const rest = words.replace(/\b(?:icloud (?:frei|free)|fmi off|ohne icloud(?: sperre| lock)?|no icloud lock)\b/g, ' ')
    .replace(/\b(?:ohne sim ?lock|sim ?lock ?frei|unlocked|debloque|entsperrt|sim ?lock(?:ed)?)\b/g, ' ');
  const locked = /\b(?:icloud (?:sp(?:err(?:e)?)?|sperre|gut|gesperrt|locked)|fmi on|aktivierungssperre|activation lock|mdm|locked|gesperrt|gespert|gesspert|bloque|bloccato|bloqueado)\b/.test(rest);
  return locked ? 'locked' : free ? 'free_by_seller' : 'unknown';
}

function iphoneModels(title) {
  const words = title.replace(/айфон/gi, 'iphone').replace(/плюс/gi, 'plus').split(/[,/&+]/).map((part, index) => {
    const text = deviceWords(part);
    return index && /iphone/i.test(title) && /^1[1-7]\b/.test(text) ? 'iphone ' + text : text;
  }).join(' ');
  const matches = [...words.matchAll(/\b(?:iphone|apple|app(e)?l|айфон)\s*(1[1-7])(e\b|\s*(?:pro max|pro|mini|plus|air)\b)?\b/g)]
    .map(match => [match[0], match[2], match[3]]);
  return [...new Set(matches.map(match => 'iPhone ' + match[1] + (match[2]
    ? match[2] === 'e' ? 'e' : ' ' + (match[2].trim() === 'mini' ? 'mini' : match[2].trim().replace(/\b\w/g, c => c.toUpperCase())) : '')))];
}

function classifyIphone(title) {
  const words = deviceWords(title);
  const cloud = iphoneCloudStatus(title);
  const models = iphoneModels(title);
  const old = /\biphone\s*(?:x[rs]?|[1-8](?:gs|s|g|c)?|se)\b/.test(words);
  const mixed = /\b(?:ipad|ipod|samsung|xiaomi|huawei|noname|poco|lg|sony|ericsson|nokia|motorola|oppo|honor|wiko|siemens|redmi)\b/.test(words);
  const bundle = multipleDevices(words) || models.length > 1 || /\b(?:pack telefonia|mehrere gerate|iphones|joblot)\b/.test(words);
  let model = models.length === 1 ? models[0] : models.length ? models.join(' / ') : 'iPhone (változat nem ismert)';
  let type = 'phone';
  const explicitPart = /\b(?:original display und gehause|nur (?:ruckseite|display|gehause|akku|platine|mainboard)|backcover|rahmen)\b/.test(words) ||
    /\b(?:display|screen|ecran|akku|battery|mainboard|motherboard|platine|gehause)\b/.test(words) &&
    !/\b(?:\d+\s*gb|smartphone|handy|gerate|defekt|gebrochen|gesprungen|schaden|beschadigt|spender|panic|kaputt|reparatur|totalschaden)\b/.test(words);
  if (bundle && mixed) type = 'not_supported_bundle';
  else if (bundle && old && !models.length) { type = 'unsupported_model'; model = 'iPhone (régebbi modell)'; }
  else if (bundle && (old || !models.length)) type = 'needs_review';
  else if (old) { type = 'unsupported_model'; model = 'iPhone (régebbi modell)'; }
  else if (mixed && !models.length) type = 'unsupported_model';
  else if (explicitPart) type = 'part';
  else if (!models.length) type = 'needs_review';
  else if (bundle) type = 'phone_bundle';
  if (cloud === 'locked' && ['phone', 'phone_bundle'].includes(type)) type = 'icloud_locked';
  return deviceResult(type, model, false, cloud);
}

function classifyGpu(title) {
  const words = deviceWords(title).replace(/\bgt x\b/g, 'gtx');
  const result = (type, model = 'Videokártya (változat nem ismert)') => deviceResult(type, model);
  const part = /\b(?:leerkarton|showpiece|deko|decor|vram chips?|chips?\b.*\bvram|ohne (?:gpu|chip|vram|pcb|board)|kein (?:pcb|gpu|chip)|no (?:vram|gpu)|nur (?:platine|lufter|kuhler)|luftereinheit|originalkuhler|kuhlkorper)\b/.test(words) ||
    /^\s*(?:original )?(?:kuhler|lufter|cooler|heatsink)\b/.test(words) ||
    /\b(?:kuhler|lufter|cooler|fan)\b/.test(words) && !/\b(?:grafikkarte|graphics card|scheda grafica|carte graphique|\d+\s*gb)\b/.test(words);
  if (part) return result('not_gpu');
  if (/\b(?:desktop pc|wlan|sata|erweiterungskarten|audio ?karten)\b/.test(words)) return result('not_gpu');
  if (/\bxg mobile 3080\b/.test(words) || /\b(?:asus tuf|msi|gigabyte)\s+3070\b/.test(words)) return result('gpu', 'RTX 30');
  const unsupported = /\b(?:gtx\s*\d|gt\s*\d|rx\s*[45]\d{2}\b|rx\s*5600|vega|quadro|rtx\s*a\d|workstation|radeon\s*(?:hd|x|\d{4})|ati\s*(?:hd|x)\d|eah\d|gf 4|ti 4200|hd\s*\d{4})/.test(words);
  const rtx = [...words.matchAll(/\brtx\s*(\d{4})(?:\s*(super|ti))?/g)];
  const rx = [...words.matchAll(/\brx\s*(\d{4})/g)];
  const lowRtx = rtx.some(match => Number(match[1]) < 2060 || match[1] === '2060' && match[2] !== 'super');
  if (unsupported || lowRtx || /\bgv rx[45]\d{2}/.test(words)) return result('unsupported_model', 'Nem támogatott videokártya');
  const families = new Set([...rtx.filter(match => /^(20|30|40|50)/.test(match[1])).map(match => 'RTX ' + match[1].slice(0, 2)),
    ...rx.filter(match => match[1] === '5700' || /^[679]\d{3}$/.test(match[1])).map(match => 'RX ' + match[1][0] + '000')]);
  if (!families.size) {
    if (/\b(?:rx\s*5[0-6]\d{2}[a-z]*|r[579](?:\s*\d{3}[a-z]*)?|r290|firepro|gpro|radeon pro|radeon vii|ati|vintage|retro|agp|x\d{3,4}|a[hkx]?\d{4}[a-z]*|6870|4890|rtx\s*\d{3}|g?ddr[235])\b/.test(words) || /\b(?:[128]\s*gb|\d+\s*mb)\b/.test(words)) {
      return result('unsupported_model', 'Nem támogatott videokártya');
    }
    if (multipleDevices(words) || /\b(?:graphics cards bundle|grafikkarten fur ersatzteile)\b/.test(words)) return result('gpu_bundle');
    return result('needs_review');
  }
  const model = [...families].join(' / ');
  const multiple = multipleDevices(words.replace(/\bventus \d+x\b/g, 'ventus')) || /\+/.test(title) && rtx.length + rx.length > 1;
  return result(multiple ? 'gpu_bundle' : 'gpu', model);
}
