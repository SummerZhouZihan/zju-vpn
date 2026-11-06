// Run with CFW's own Electron in Node mode; reuse its bundled YAML library.
const fs = require('fs');
const path = require('path');
const cp = require('child_process');
const [exe, dataDir, coreExe, action = 'plan'] = process.argv.slice(2);
if (!['plan', 'apply'].includes(action)) throw new Error('Expected plan or apply.');
const yaml = require(path.join(path.dirname(exe), 'resources', 'app.asar', 'node_modules', 'yaml'));
const parserCode = fs.readFileSync(path.join(__dirname, 'parser.cjs'), 'utf8');
const parse = require('./parser.cjs').parse;
const settingsPath = path.join(dataDir, 'cfw-settings.yaml');
const listPath = path.join(dataDir, 'profiles', 'list.yml');
const read = p => yaml.parse(fs.readFileSync(p, 'utf8')) || {};
const list = read(listPath);
const entry = list.files && list.files[list.index || 0];
if (!entry) throw new Error('No selected Clash subscription/profile.');
const profilePath = path.resolve(dataDir, 'profiles', String(entry.time));
if (path.dirname(profilePath) !== path.resolve(dataDir, 'profiles')) throw new Error('Invalid profile filename');
const settings = read(settingsPath);
const parsers = settings.profileParsersText ? (yaml.parse(settings.profileParsersText) || {}).parsers || [] : [];
if (!Array.isArray(parsers)) throw new Error('Existing CFW parsers must be an array');
const updatedParsers = parsers.filter(p => !p['zju-connect-campus']);
updatedParsers.push({ reg: '^https?://', 'zju-connect-campus': true, code: parserCode });
settings.profileParsersText = yaml.stringify({ parsers: updatedParsers });
const bypass = settings.bypassText ? yaml.parse(settings.bypassText) : {};
const isCampusBypass = value => value === '10.*' || /^172\.(1[6-9]|2\d|3[01])\.\*$/.test(value);
if (bypass && Array.isArray(bypass.bypass)) {
  bypass.bypass = bypass.bypass.filter(value => !isCampusBypass(value));
  settings.bypassText = yaml.stringify(bypass);
}
const profileContent = fs.readFileSync(profilePath, 'utf8');
const updatedProfile = parse({ content: profileContent }, { yaml });
const desired = new Map([[settingsPath, yaml.stringify(settings)], [profilePath, updatedProfile]]);
// base config must stay intact: CFW merges the selected profile itself on restart.
const changed = [...desired].filter(([p, content]) => fs.readFileSync(p, 'utf8') !== content);
if (action === 'plan') {
  const base = read(path.join(dataDir, 'config.yaml'));
  console.log(JSON.stringify({ changed: changed.length > 0, port: base['mixed-port'] || base.port || 7890,
    profile: path.basename(profilePath) }));
} else if (action === 'apply') {
  const checkFile = path.join(dataDir, `zju-campus-check-${process.pid}.yaml`);
  try {
    fs.writeFileSync(checkFile, updatedProfile, { encoding: 'utf8', flag: 'wx' });
    const result = cp.spawnSync(coreExe, ['-t', '-d', dataDir, '-f', checkFile], { encoding: 'utf8', windowsHide: true, timeout: 30000 });
    if (result.error || result.status !== 0) {
      // Do not print the profile: it contains subscription credentials.
      throw new Error('Clash core rejected campus profile; existing files were not modified.');
    }
  } finally {
    if (fs.existsSync(checkFile)) fs.unlinkSync(checkFile);
  }
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  const written = [];
  try {
    for (const [p, content] of changed) {
      const backup = `${p}.bak-zju-${stamp}`;
      fs.copyFileSync(p, backup, fs.constants.COPYFILE_EXCL);
      written.push([p, backup]);
      fs.writeFileSync(p, content, 'utf8');
      console.log(`[zju-vpn] Updated ${p}; backup: ${backup}`);
    }
  } catch (error) {
    for (const [p, backup] of written.reverse()) fs.copyFileSync(backup, p);
    throw error;
  }
} else {
  throw new Error('Unknown action');
}
