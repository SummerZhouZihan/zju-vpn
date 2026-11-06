const assert = require('assert');
const path = require('path');
const yaml = process.argv[2]
  ? require(path.join(path.dirname(process.argv[2]), 'resources', 'app.asar', 'node_modules', 'yaml'))
  : require('yaml');
const parse = require('../src/clash/parser.cjs').parse;
const original = {
  'mixed-port': 7890,
  proxies: [{ name: 'existing-node', type: 'socks5', server: '127.0.0.1', port: 1234 }],
  'proxy-groups': [{ name: 'existing-group', type: 'select', proxies: ['existing-node'] }],
  rules: ['DOMAIN-SUFFIX,zju.edu.cn,DIRECT', 'DOMAIN-SUFFIX,example.com,existing-group', 'MATCH,DIRECT']
};
const once = parse(yaml.stringify(original), { yaml });
const actual = yaml.parse(once);
assert.deepStrictEqual(actual.proxies[0], original.proxies[0]);
assert.deepStrictEqual(actual['proxy-groups'][0], original['proxy-groups'][0]);
assert.strictEqual(actual['mixed-port'], 7890);
const campusRule = actual.rules.indexOf('DOMAIN-SUFFIX,zju.edu.cn,Campus');
assert(campusRule > actual.rules.indexOf('DOMAIN,vpn.zju.edu.cn,DIRECT'));
assert(campusRule < actual.rules.indexOf('DOMAIN-SUFFIX,zju.edu.cn,DIRECT'));
assert(actual.rules.includes('DOMAIN-SUFFIX,example.com,existing-group'));
assert.strictEqual(actual.rules.at(-1), 'MATCH,DIRECT');
assert.strictEqual(parse(once, { yaml }), once, 'Repeated setup must not duplicate rules/nodes');
assert.strictEqual(parse({ content: once }, { yaml }), once, 'Support both CFW parser calling conventions');
assert.throws(() => parse('just a scalar', { yaml }));
const campus = actual['proxy-groups'].find(g => g.name === 'Campus');
assert.strictEqual(campus.type, 'fallback');
assert.deepStrictEqual(campus.proxies, ['DIRECT', 'ZJUconnect'], 'Direct access must have priority');
assert.strictEqual(campus.url, 'https://www.cc98.org/');
assert.strictEqual(campus.interval, 60);
assert.strictEqual(campus.lazy, false);
assert(actual.rules.includes('PROCESS-NAME,zju-connect.exe,DIRECT'));

// Upgrade older generated groups and preserve references from other groups.
const legacy = yaml.parse(once);
legacy['proxy-groups'] = legacy['proxy-groups'].filter(g => g.name !== 'Campus');
legacy['proxy-groups'].push({ name: 'OldCampus', type: 'select', proxies: ['ZJUconnect', 'DIRECT'] });
legacy['proxy-groups'].push({ name: 'Other', type: 'select', proxies: ['OldCampus', 'existing-node'] });
legacy.rules = legacy.rules.map(r => r.replace(',Campus', ',OldCampus'));
const migratedText = parse(yaml.stringify(legacy), { yaml });
const migrated = yaml.parse(migratedText);
assert(!migrated['proxy-groups'].some(g => g.name === 'OldCampus'));
assert(migrated['proxy-groups'].find(g => g.name === 'Other').proxies.includes('Campus'));
assert(!migrated.rules.some(r => r.includes('OldCampus')));
assert.strictEqual(parse(migratedText, { yaml }), migratedText);
console.log('Campus parser behavior: OK');
