const SUPPLEMENTARY_QUERIES = {
  consoles: { DE: [{ query: 'ps5 defekt', word: 'defekt' }, { query: 'xbox series defekt', word: 'defekt' }] },
  controllers: {
    DE: [{ query: 'ps5 controller defekt', word: 'defekt' }, { query: 'xbox controller defekt', word: 'defekt' }],
    FR: [{ query: 'ps5 controller hs', word: 'hs' }, { query: 'xbox controller hs', word: 'hs' }],
  },
};
const SUPPLEMENTARY_CONDITIONS = { consoles: ['3000'], controllers: ['3000'] };

function supplementaryFaultInTitle(title, word, group) {
  if (!isDiagnosticFaultTitle(title, [word])) return false;
  const words = diagnosticTitleWords(title);
  if (/\b(?:voll funktionsfahig|pas (?:du tout )?hs|non hs|aucune panne|sans defaut)\b/.test(words)) return false;
  const controllerAccessories = 'stick modul|stickmodul|joystick modul|platine|mainboard|gehause|shell|cover|paddle|ladestation|charging station|akku|batterie|usb kabel|kabel|cable|netzteil|ladegerat|headset';
  const accessories = group === 'consoles'
    ? 'controller|kontroller|manette|mando|dualsense|gamepad|' + controllerAccessories
    : controllerAccessories;
  const fault = diagnosticTitleWords(word) + (word === 'defekt' ? '[a-z]*' : '');
  const accessoryFault = new RegExp('\\b(?:' + accessories + ')s?\\s+(?:(?:ist|sind|est|is|nur|teilweise|leicht)\\s+)*' + fault + '\\b|' +
    '\\b' + fault + '\\s+(?:(?:der|des|du|de la|the)\\s+)?(?:' + accessories + ')s?\\b', 'g');
  const withoutAccessoryFault = title.split(/[,;|\n]+/).map(part =>
    diagnosticTitleWords(part).replace(accessoryFault, ' ')).join(' ');
  return isDiagnosticFaultTitle(withoutAccessoryFault, [word]);
}
