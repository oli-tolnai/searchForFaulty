const LEGACY_CONTROLLER_MODELS = [
  ['PS4 / DualShock 4', /\b(?:ps\s*4|play\s*station\s*4|dual\s*shock\s*4|cuh[\s-]*zct\w*)\b/],
  ['PS3', /\b(?:ps\s*3|play\s*station\s*3|sixaxis|dual\s*shock\s*3)\b/],
  ['PS1 / PS2', /\b(?:ps\s*[12]|play\s*station\s*[12]|psx|psone|scph[\s-]*\d+)\b/],
  ['Xbox One', /\b(?:xbox\s*one|1537|1697|1708)\b/],
  ['Xbox 360', /\bxbox\s*360\b/],
  ['Xbox Elite Series 1', /\b(?:1698|elite(?:\s+(?:wireless|controller|series|serie|v))*[\s-]+1)\b/],
];

function classifyController(value) {
  const title = value.toLowerCase().replace(/[‐‑–—]/g, '-')
    .replace(/\b(\d+)[x×](?=dual|controller|xbox|sony|ps)/g, '$1x ');
  const primary = title.replace(/\b(?:kompatibel mit|compatible with)\b.*$/, '')
    .replace(/\b(?:für|for|pour)\s+(?:microsoft\s+)?xbox\s+series\b.*$/, '');
  const result = (type, model = 'Ellenőrzendő', scuf = false) => ({
    item_type: type, console_model: model, is_scuf: scuf, is_banned: false,
  });
  const legacy = LEGACY_CONTROLLER_MODELS.find(([, pattern]) => pattern.test(primary));
  if (legacy) return result('unsupported_model', legacy[0]);

  const controller = /\b(?:controller|kontroller|game\s*pad|manette)\b/;
  const part = /\b(?:stick[\s-]*modul(?:e|s|es)?|joystick[\s-]*modul(?:e|s|es)?|mainboards?|motherboards?|platinen?|(?:ersatz)?gehäuse|abdeckung|shells?|covers?|paddles?|ladestation(?:en)?|ladegerät|charging[\s-]*(?:dock|station)|chargers?|akku(?:s)?|batter(?:y|ies)|lenkrad|steering wheel|racing wheel|wheel|headsets?|schutzhülle|etui|tasche|case|hall effect sensors?|trigger (?:spring|assembly)|usb[ -]?c? (?:port|buchse))\b/;
  const partOnly = /\b(?:nur|only|allein)\s+(?:der |die |das |the )?/;
  const explicitPart = partOnly.test(title) && part.test(title.replace(/^.*\b(?:nur|only|allein)\s+/, '').split(/\s+/).slice(0, 3).join(' '));
  const partIndex = title.search(part);
  const accessoryWithController = /\b(?:mit|with|inkl\.?|including|plus|avec)\s+|\+\s*/;
  const bundledPart = partIndex >= 0 && accessoryWithController.test(title.slice(0, partIndex)) &&
    controller.test(title.slice(0, partIndex));
  const fullController = /\b(?:komplett(?:er|en|es)?|complete|vollständig)\b/.test(title) ||
    /\b(?:controller|kontroller|gamepad|manette)\s+(?:defekt|teildefekt|kaputt|faulty|broken)\b/.test(title.slice(0, partIndex)) ||
    bundledPart;
  const console = /\b(?:825\s*gb|[12]\s*tb|(?:blu-ray\/)?(?:disc|disk|digital)\s+edition|konsole|console)\b/.test(title);
  if (explicitPart || /\b(?:ohne|without|sans)\s+(?:den |the |a )?(?:controller|kontroller|gamepad|manette)\b/.test(title) ||
      console || (partIndex >= 0 && !fullController)) return result('not_controller');

  if (/\b(?:pdp|power\s*a|thrustmaster|nacon|victrix|turtle\s*beach|hori|8\s*bit\s*do|gamesir|razer|logitech|hyperkin|bigbig\s*won|gulikit|snakebyte|tr\u00fcst|trust|speedlink|mad\s*catz|easy\s*smx)\b/.test(title)) {
    return result('third_party');
  }

  const quantities = title.replace(/\b(?:dualsense\s*5|play\s*station\s*(?:sony\s*)?5|ps\s*5|series\s*2|elite\s*2)\b/g, ' ');
  const multi = /\b(?:konvolut|lot|posten|mehrere|bundle of|[2-9]\d*\s*er\s*set)\b|\b(?:[2-9]|[1-9]\d+)\s*(?:[x×](?![a-z0-9])|stück\b|pcs\b|controller\b|kontroller\b)/.test(quantities) ||
    (/\bbundle\b/.test(title) && !bundledPart);
  const edge = /\bcfi[\s-]*zcp1\w*\b|\bedge\b/.test(title);
  const scuf = /\bscuff?\b/.test(title);
  const dualSense = /\bcfi[\s-]*zct1\w*\b|\bdual\s*sense\b/.test(title) ||
    (/\b(?:ps\s*5|play\s*station\s*(?:sony\s*)?5)\b/.test(title) && controller.test(title));
  const elite = /\b1797\b|\belite(?:\s+(?:wireless|controller|series|serie|v))*[\s-]+(?:2|ii)\b/.test(title);
  const series = /\b1914\b/.test(title) ||
    (controller.test(title) && /\b(?:series\s*[xs]\b|xbox\s+series\b)/.test(title));
  const xboxWireless = /\bxbox(?:\s+\w+){0,3}\s+wireless\s+(?:controller|gamepad)\b/.test(title) ||
    /\bwireless\s+controller\s+(?:for|für)\s+xbox\b/.test(title);
  const playStationModel = edge ? 'DualSense Edge' : scuf ? 'DualSense (Scuf)' : dualSense ? 'DualSense' : null;
  const xboxModel = elite ? 'Xbox Elite Series 2' : series ? 'Xbox Series kontroller'
    : xboxWireless ? 'Xbox kontroller (generáció nem ismert)' : null;
  const model = playStationModel && xboxModel ? null : playStationModel || xboxModel;
  if (multi) return result('controller_bundle', model || 'Ellenőrzendő', scuf && !!playStationModel);
  return model ? result('controller', model, scuf && !!playStationModel) : result('needs_review');
}
