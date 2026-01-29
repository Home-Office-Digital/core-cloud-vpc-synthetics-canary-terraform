'use strict';

const net = require('node:net');
const synthetics = require('Synthetics');
const log = require('SyntheticsLogger');

const env = (k, d) => (process.env[k] ?? d);

// Environment variables
const DEST_IP = env('DEST_IP');
const ALLOW = env('ALLOW_PORTS', '').split(',').map(s => s.trim()).filter(Boolean).map(Number);
const DENY = env('DENY_PORTS', '').split(',').map(s => s.trim()).filter(Boolean).map(Number);
const TIMEOUT = Number(env('CONNECT_TIMEOUT_MS', '3000'));
const SCAN_START = Number(env('SCAN_START', '1'));
const SCAN_END = Number(env('SCAN_END', '1024'));
const ALERT_ON_OPEN_PORTS = env('ALERT_ON_OPEN_PORTS', 'true').toLowerCase() === 'true';

const validatePort = p => Number.isInteger(p) && p > 0 && p <= 65535;

// TCP connectivity helper
async function tryConnect(host, port, timeoutMs) {
  return new Promise((resolve) => {
    const socket = net.createConnection({ host, port });
    const timer = setTimeout(() => {
      socket.destroy();
      resolve(false);
    }, timeoutMs);

    socket.on('connect', () => {
      clearTimeout(timer);
      socket.end();
      resolve(true);
    });

    socket.on('error', () => {
      clearTimeout(timer);
      resolve(false);
    });
  });
}

// Scan ports in a range
async function scanPorts(host, start = SCAN_START, end = SCAN_END, timeoutMs = TIMEOUT) {
  const openPorts = [];
  const checks = [];

  for (let port = start; port <= end; port++) {
    checks.push((async () => {
      const ok = await tryConnect(host, port, timeoutMs);
      if (ok) openPorts.push(port);
    })());
  }

  await Promise.all(checks);
  return openPorts;
}

exports.handler = async () => {
  if (!DEST_IP) throw new Error('DEST_IP environment variable is required');

  let allowedPorts = ALLOW.filter(validatePort);
  let deniedPorts = DENY.filter(validatePort);
  const checks = [];

  // Summary fields
  let scanned = false;
  let summaryOpenPorts = [];
  let unexpectedOpenPorts = [];

  // If ALLOW_PORTS is empty, perform scan for compliance checking
  if (allowedPorts.length === 0) {
    scanned = true;
    log.info(`ALLOW_PORTS not provided. Scanning ports ${SCAN_START}-${SCAN_END}...`);
    const openPorts = await scanPorts(DEST_IP, SCAN_START, SCAN_END);
    summaryOpenPorts = openPorts.slice();

    if (openPorts.length === 0) {
      log.info('Firewall DENY rule active: all scanned ports are blocked.');
      // Continue to validate explicit DENY ports
    } else {
      // Unexpected open ports found when no explicit ALLOW provided
      unexpectedOpenPorts = openPorts.slice();

      // Emit summary before alerting (so it’s visible in logs even on failure)
      const preAlertSummary = {
        destIp: DEST_IP,
        scan: { range: { start: SCAN_START, end: SCAN_END }, openPorts: summaryOpenPorts },
        allowedPorts: allowedPorts,      // still empty here
        deniedPorts: deniedPorts,
        unexpectedOpenPorts,
        alertOnOpenPorts: ALERT_ON_OPEN_PORTS,
        timestamp: new Date().toISOString()
      };
      log.info('Summary (pre-alert): ' + JSON.stringify(preAlertSummary));

      if (ALERT_ON_OPEN_PORTS) {
        log.error(`Unexpected open ports detected: ${openPorts.join(', ')}`);
        throw new Error(`Firewall DENY rule violation: unexpected open ports found (${openPorts.join(', ')})`);
      } else {
        log.warn(`Unexpected open ports detected (no alert mode): ${openPorts.join(', ')}`);
        // Classify allowed vs denied: treat non-deny open ports as allowed for subsequent checks
        allowedPorts = openPorts.filter(p => !deniedPorts.includes(p));
      }
    }
  }

  // Perform ALLOW checks
  for (const p of allowedPorts) {
    checks.push(synthetics.executeStep(`tcp-allow-${p}`, async () => {
      const ok = await tryConnect(DEST_IP, p, TIMEOUT);
      log.info(`ALLOW check: ${DEST_IP}:${p} -> ${ok ? 'CONNECTED' : 'FAILED'}`);
      if (!ok) throw new Error(`Expected ALLOW, but could not connect to ${DEST_IP}:${p}`);
    }));
  }

  // Perform DENY checks
  for (const p of deniedPorts) {
    checks.push(synthetics.executeStep(`tcp-deny-${p}`, async () => {
      const ok = await tryConnect(DEST_IP, p, TIMEOUT);
      log.info(`DENY check: ${DEST_IP}:${p} -> ${ok ? 'CONNECTED' : 'BLOCKED'}`);
      if (ok) throw new Error(`Expected DENY, but connection to ${DEST_IP}:${p} succeeded`);
    }));
  }

  await Promise.all(checks);

  // Final JSON summary report
  const summary = {
    destIp: DEST_IP,
    scan: scanned ? { range: { start: SCAN_START, end: SCAN_END }, openPorts: summaryOpenPorts } : null,
    allowedPorts,
    deniedPorts,
    unexpectedOpenPorts,
    alertOnOpenPorts: ALERT_ON_OPEN_PORTS,
    timestamp: new Date().toISOString()
  };

  log.info('Summary: ' + JSON.stringify(summary));
};