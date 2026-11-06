'use strict';
// Isolated real-core test. No campus credentials, live profile, or Internet probe.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const net = require('node:net');
const http = require('node:http');
const { spawn } = require('node:child_process');
const { once } = require('node:events');
const core = process.argv[2];
if (!core) throw new Error('Usage: node tests/fallback-core.test.cjs <clash-core.exe> <Country.mmdb>');
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
let directUp = true;
const probe = http.createServer((req, res) => {
  if (!directUp) return req.socket.destroy();
  res.writeHead(200, { 'Content-Length': '0', Connection: 'close' });
  res.end();
});
// Minimal SOCKS5 fixture: its health-check requests always receive HTTP 200.
const standby = net.createServer(socket => {
  let state = 0;
  let buffer = Buffer.alloc(0);
  socket.on('error', () => {});
  socket.on('data', chunk => {
    buffer = Buffer.concat([buffer, chunk]);
    if (state === 0) {
      if (buffer.length < 2 || buffer.length < 2 + buffer[1]) return;
      buffer = buffer.subarray(2 + buffer[1]);
      socket.write(Buffer.from([5, 0]));
      state = 1;
    }
    if (state === 1) {
      if (buffer.length < 5) return;
      const length = buffer[3] === 1 ? 10 : buffer[3] === 4 ? 22 : 7 + buffer[4];
      if (buffer.length < length) return;
      buffer = buffer.subarray(length);
      socket.write(Buffer.from([5, 0, 0, 1, 127, 0, 0, 1, 0, 0]));
      state = 2;
    }
    if (state === 2 && buffer.includes('\r\n\r\n')) {
      state = 3;
      socket.end('HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n');
    }
  });
});
async function listen(server) {
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  return server.address().port;
}
async function main() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'zju-vpn-core-test-'));
  let child;
  try {
    const probePort = await listen(probe);
    const socksPort = await listen(standby);
    const reservation = net.createServer();
    const controllerPort = await listen(reservation);
    await new Promise(resolve => reservation.close(resolve));
    if (!process.argv[3]) throw new Error('Pass an existing Country.mmdb to avoid a core download.');
    fs.copyFileSync(process.argv[3], path.join(dir, 'Country.mmdb'));
    const config = {
      'external-controller': `127.0.0.1:${controllerPort}`,
      'log-level': 'silent',
      mode: 'rule',
      proxies: [{ name: 'ZJUconnect', type: 'socks5', server: '127.0.0.1', port: socksPort }],
      'proxy-groups': [{ name: 'Campus', type: 'fallback', proxies: ['DIRECT', 'ZJUconnect'],
        url: `http://127.0.0.1:${probePort}/`, interval: 1, lazy: false }],
      rules: ['MATCH,Campus']
    };
    const file = path.join(dir, 'config.yaml');
    fs.writeFileSync(file, JSON.stringify(config));
    child = spawn(core, ['-d', dir, '-f', file], { windowsHide: true, stdio: 'ignore' });
    const exit = once(child, 'exit');
    async function waitFor(expected) {
      const deadline = Date.now() + 15000;
      while (Date.now() < deadline) {
        if (child.exitCode !== null) throw new Error('Isolated core exited unexpectedly');
        try {
          const response = await fetch(`http://127.0.0.1:${controllerPort}/proxies/Campus`,
            { signal: AbortSignal.timeout(1000) });
          if ((await response.json()).now === expected) return;
        } catch { /* Controller startup and health-check transitions take time. */ }
        await sleep(200);
      }
      assert.fail(`Fallback did not select ${expected}`);
    }
    await waitFor('DIRECT');
    directUp = false;
    await waitFor('ZJUconnect');
    directUp = true;
    await waitFor('DIRECT');
    child.kill();
    await exit;
    child = null;
    console.log('Real core fallback: DIRECT -> ZJUconnect -> DIRECT: OK');
  }
  finally {
    if (child) { const ended = once(child, 'exit'); child.kill(); await ended; }
    probe.closeAllConnections();
    await Promise.all([new Promise(resolve => probe.close(resolve)), new Promise(resolve => standby.close(resolve))]);
    // Delete only a verified, task-owned temporary directory.
    assert.equal(path.dirname(dir), path.resolve(os.tmpdir()));
    assert(path.basename(dir).startsWith('zju-vpn-core-test-'));
    fs.rmSync(dir, { recursive: true });
  }
}
main().catch(error => { console.error(error.message); process.exitCode = 1; });
