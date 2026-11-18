import assert from 'node:assert/strict';
import { test } from 'node:test';
import { fixture, runtime } from './helpers.mjs';

const app = runtime();
for (const word of ['Gesspert','Gespert','Icload Sperre','iClod Sperre','iCloud Sp','iCloud Sperr','iCloud Gut für Ersatzteile']) {
  test('conservative lock handling: ' + word, () => {
    assert.equal(app.run('classifyIphone','iPhone 13 ' + word).item_type,'icloud_locked');
  });
}
test('seller free claims and SIM unlock remain distinct from locks after typo normalization', () => {
  assert.equal(app.run('iphoneCloudStatus','iClod frei FMI OFF unlocked'),'free_by_seller');
  assert.equal(app.run('iphoneCloudStatus','iPhone 13 entsperrt ohne Simlock'),'unknown');
});
test('supported-only, mixed-brand and older-only phone bundles are distinct', () => {
  assert.equal(app.run('classifyIphone','2x iPhone 13 und iPhone 14').item_type,'phone_bundle');
  assert.equal(app.run('classifyIphone','iPhone 13 Samsung Konvolut').item_type,'not_supported_bundle');
  assert.equal(app.run('classifyIphone','Konvolut 2x iPhone 5c 3GS').item_type,'unsupported_model');
});

const expectedGpu = [
  'gpu_bundle','unsupported_model','unsupported_model','unsupported_model','needs_review','unsupported_model',
  'unsupported_model','gpu_bundle','gpu','gpu_bundle','unsupported_model','unsupported_model','unsupported_model',
  'needs_review','unsupported_model','unsupported_model','not_gpu','unsupported_model','unsupported_model',
  'needs_review','needs_review','unsupported_model','needs_review','gpu_bundle','not_gpu','gpu',
];
const gpu = fixture('review_titles_2026-11-17').find(group => group.device_group === 'gpu');
assert.equal(gpu.titles.length,expectedGpu.length);
gpu.titles.forEach((title,index) => test('measured GPU review title: ' + title, () => {
  assert.equal(app.run('classifyGpu',title).item_type,expectedGpu[index]);
}));
test('measured review set materially shrinks without forcing unidentified models', () => {
  for (const [group,max] of [['iphone',100],['gpu',5]]) {
    const titles=fixture('review_titles_2026-11-17').find(row => row.device_group===group).titles;
    const count=titles.filter(title=>app.run(group==='iphone'?'classifyIphone':'classifyGpu',title).item_type==='needs_review').length;
    assert.ok(count<=max,group+': '+count);
  }
});

test('per-group filters and tab visibility synchronize independently with validation', () => {
  const filter={...app.run('alertDefaults',{models:[],include_unknown_shipping:true,enabled:true}),order:'total',
    min_price:10,max_price:100,include_keywords:['Drift'],only_icloud_free:true};
  const ops=[{type:'setting_set',op_id:'group-filter-test-1',key:'search_filter_iphone',value:filter},
    {type:'setting_set',op_id:'group-filter-test-2',key:'search_tabs',value:{visible_groups:['iphone','gpu'],selected_groups:['iphone']}}];
  assert.equal(app.post('state_apply',{ops}).ok,true);
  const rows=app.post('state_get',{since_revision:0}).data.settings;
  assert.equal(rows.find(row=>row.key==='search_filter_iphone').value.min_price,10);
  assert.deepEqual(rows.find(row=>row.key==='search_tabs').value.visible_groups,['iphone','gpu']);
  assert.equal(app.post('state_apply',{ops:[{...ops[0],op_id:'bad-search-filter-1',value:{...filter,min_price:-1}}]}).ok,false);
  assert.equal(app.post('state_apply',{ops:[{...ops[1],op_id:'bad-search-tabs-1',value:{visible_groups:[],selected_groups:['iphone']}}]}).ok,false);
});
test('notification presets enforce new price, iCloud, accessory and vendor conditions', () => {
  const rule={models:[],device_groups:['iphone','gpu','controllers','consoles'],enabled:true,include_unknown_shipping:true};
  const base={...app.run('normalizeListing',fixture('search').itemSummaries[1],new Date()),device_group:'iphone',item_type:'phone',console_model:'iPhone 13',icloud_status:'unknown'};
  assert.equal(app.run('alertMatches',base,{...rule,only_icloud_free:true}),false);
  assert.equal(app.run('alertMatches',{...base,icloud_status:'free_by_seller'},{...rule,only_icloud_free:true,min_price:20}),true);
  assert.equal(app.run('alertMatches',base,{...rule,min_price:40}),false);
  assert.equal(app.run('alertMatches',{...base,device_group:'controllers',item_type:'third_party'},{...rule,include_third_party:true}),true);
  assert.equal(app.run('alertMatches',{...base,device_group:'consoles',item_type:'mainboard'},{...rule,include_mainboards:true}),true);
  assert.equal(app.run('alertMatches',{...base,device_group:'gpu',item_type:'gpu',console_model:'RTX 30'},{...rule,gpu_vendor:'AMD'}),false);
});
