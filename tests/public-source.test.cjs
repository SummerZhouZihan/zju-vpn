'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const files = require('../public-files.json');
const han = /\p{Script=Han}/u;
const excluded = new Set(['.git', 'node_modules', 'dist', 'release', 'coverage']);
assert.equal(new Set(files).size, files.length, 'Duplicate public file');
for (const relative of files) {
  assert(!path.isAbsolute(relative) && !relative.split('/').includes('..'), 'Invalid public path');
  assert(!han.test(relative), 'Localized public filename');
  if (relative.endsWith('.md')) {
    assert(relative === 'README.md' || relative.startsWith('docs/'), `Supporting documentation must live in docs: ${relative}`);
  }
  const fullPath = path.resolve(root, relative);
  assert(fullPath.startsWith(root + path.sep), 'Public path escapes the source tree');
  assert(fs.statSync(fullPath).isFile(), `Missing public file: ${relative}`);
  for (let current = fullPath; current !== root; current = path.dirname(current)) {
    assert(!fs.lstatSync(current).isSymbolicLink(), `Symlink in public path: ${relative}`);
  }
  const content = fs.readFileSync(fullPath, 'utf8');
  if (relative !== 'README.md') {
    assert(!han.test(content), `Localized source: ${relative}`);
    const decoded = content.replace(/\\u([0-9a-f]{4})/gi, (_, hex) => String.fromCharCode(parseInt(hex, 16)));
    if (relative !== 'resources/locales/zh-CN.json') {
      assert(!han.test(decoded), `Localized escape outside the translation resource: ${relative}`);
    }
  }
  if (/^(src|scripts)\//.test(relative)) {
    assert(!/paperread/i.test(content), `Optional integration leaked into the core: ${relative}`);
  }
  assert(!/-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/.test(content), `Private key: ${relative}`);
  assert(!/C:[\\/]+Users[\\/]+(?!<|example\b|USERNAME\b)[a-z0-9_.-]+/i.test(content), `Personal path: ${relative}`);
}
function walk(directory, prefix = '') {
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    if (excluded.has(entry.name) || /^zju-connect-windows-/.test(entry.name)) continue;
    const relative = prefix + entry.name;
    assert(!han.test(relative), `Localized filename: ${relative}`);
    assert(!entry.isSymbolicLink(), `Unexpected symlink: ${relative}`);
    if (entry.isDirectory()) walk(path.join(directory, entry.name), relative + '/');
    else assert(files.includes(relative), `Unlisted file in source tree: ${relative}`);
  }
}
walk(root);
const sample = fs.readFileSync(path.join(root, 'config/zju-connect.example.toml'), 'utf8');
assert(/^username = ""$/m.test(sample) && /^password = ""$/m.test(sample), 'Sample contains credentials');
assert(/^socks_bind = "127\.0\.0\.1:1090"$/m.test(sample), 'SOCKS must use loopback');
assert(/^http_bind = "127\.0\.0\.1:1091"$/m.test(sample), 'HTTP must use loopback');
const english = require('../resources/locales/en.json');
const chinese = require('../resources/locales/zh-CN.json');
assert.deepEqual(Object.keys(chinese).sort(), Object.keys(english).sort(), 'Translation keys must match');
for (const key of Object.keys(english)) {
  assert(typeof english[key] === 'string' && english[key].length > 0, `Missing English text: ${key}`);
  assert(typeof chinese[key] === 'string' && chinese[key].length > 0, `Missing translated text: ${key}`);
  assert.deepEqual(chinese[key].match(/\{\d+\}/g), english[key].match(/\{\d+\}/g), `Translation placeholders differ: ${key}`);
}
console.log(`Public source policy: OK (${files.length} files)`);
