// Used both by the local installer and CFW's subscription parser.
module.exports.parse = function (input, { yaml }) {
  // CFW subscription parsers receive raw YAML; mixins receive { content }.
  const content = typeof input === 'string' ? input : input.content;
  const config = yaml.parse(content);
  if (!config || typeof config !== 'object' || Array.isArray(config)) {
    throw new Error('Expected a Clash YAML mapping');
  }
  const campus = 'Campus';
  // Migrate the previous generated group without embedding localized names.
  const oldGroups = new Set((config['proxy-groups'] || []).filter(g =>
    g.name !== campus && g.type === 'select' && Array.isArray(g.proxies) &&
    g.proxies.length === 2 && g.proxies.includes('ZJUconnect') && g.proxies.includes('DIRECT') &&
    (config.rules || []).includes(`DOMAIN-SUFFIX,zju.edu.cn,${g.name}`)
  ).map(g => g.name));
  config.proxies = (config.proxies || []).filter(p => p.name !== 'ZJUconnect');
  config.proxies.push({ name: 'ZJUconnect', type: 'socks5', server: '127.0.0.1', port: 1090, udp: true });
  config['proxy-groups'] = (config['proxy-groups'] || []).filter(p => p.name !== campus && !oldGroups.has(p.name));
  // Connectivity to an internal resource determines reachability, not location.
  config['proxy-groups'].push({ name: campus, type: 'fallback', proxies: ['DIRECT', 'ZJUconnect'],
    url: 'https://www.cc98.org/', interval: 60, lazy: false });
  for (const group of config['proxy-groups']) {
    if (Array.isArray(group.proxies)) group.proxies = group.proxies.map(p => oldGroups.has(p) ? campus : p);
  }
  config.rules = (config.rules || []).map(rule => rule.split(',').map((part, index) =>
    index > 0 && oldGroups.has(part) ? campus : part).join(','));
  const rules = [
    'PROCESS-NAME,zju-connect.exe,DIRECT',
    'DOMAIN,vpn.zju.edu.cn,DIRECT',
    'DOMAIN,rvpn.zju.edu.cn,DIRECT',
    'DOMAIN,webvpn.zju.edu.cn,DIRECT',
    `DOMAIN-SUFFIX,zju.edu.cn,${campus}`,
    `DOMAIN-SUFFIX,zjusec.com,${campus}`,
    `DOMAIN-SUFFIX,cc98.org,${campus}`,
    `IP-CIDR,10.0.0.0/8,${campus},no-resolve`,
    `IP-CIDR,172.16.0.0/12,${campus},no-resolve`
  ];
  config.rules = rules.concat((config.rules || []).filter(r => !rules.includes(r)));
  return yaml.stringify(config);
};
