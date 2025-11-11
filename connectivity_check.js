'use strict';

const net = require('net');
const synthetics = require('Synthetics');
const log = require('SyntheticsLogger');

const env = (k, d) => (process.env[k] ?? d);
const DEST_IP = env('DEST_IP');
const ALLOW = env('ALLOW_PORTS', '').split(',').map(s => s.trim()).filter(Boolean).map(Number);
const DENY  = env('DENY_PORTS',  '').split(',').map(s => s.trim()).filter(Boolean).map(Number);
const TIMEOUT = Number(env('CONNECT_TIMEOUT_MS', '3000'));

async function tryConnect(host, port, timeoutMs) {
  return new Promise((resolve, reject) => {
    const socket = net.createConnection({ host, port, timeout: timeoutMs }, () => {
      socket.end();
      resolve(true);
    });
    socket.on('timeout', () => { socket.destroy(); resolve(false); });
    socket.on('error', () => { resolve(false); });
  });
}

const customerCanary = {
  tcpCheck: async () => {
    if (!DEST_IP) throw new Error('DEST_IP env var is required');

    const checks = [];

    for (const p of ALLOW) {
      checks.push(synthetics.executeStep(`tcp-allow-${p}`, async () => {
        const ok = await tryConnect(DEST_IP, p, TIMEOUT);
        log.info(`ALLOW check: ${DEST_IP}:${p} -> ${ok ? 'CONNECTED' : 'FAILED'}`);
        if (!ok) throw new Error(`Expected ALLOW, but could not connect to ${DEST_IP}:${p}`);
      }));
    }

    for (const p of DENY) {
      checks.push(synthetics.executeStep(`tcp-deny-${p}`, async () => {
        const ok = await tryConnect(DEST_IP, p, TIMEOUT);
        log.info(`DENY check: ${DEST_IP}:${p} -> ${ok ? 'CONNECTED' : 'BLOCKED/FAILED'}`);
        if (ok) throw new Error(`Expected DENY, but connection to ${DEST_IP}:${p} succeeded`);
      }));
    }

    await Promise.all(checks);
  }
};

exports.handler = customerCanary.tcpCheck;