'use strict';

const net = require('node:net');
const synthetics = require('Synthetics');
const log = require('SyntheticsLogger');

const env = (k, d) => (process.env[k] ?? d);
const SCAN_CONCURRENCY = 25;

// Environment variables
const TARGET_IPS = (() => {
  const targetIps = env('TARGET_IPS', '')
    .split(',')
    .map(s => s.trim())
    .filter(Boolean);

  if (targetIps.length > 0) {
    return targetIps;
  }

  const legacyTargetIp = env('DEST_IP', '').trim();
  return legacyTargetIp ? [legacyTargetIp] : [];
})();
const ALLOW = env('ALLOW_PORTS', '').split(',').map(s => s.trim()).filter(Boolean).map(Number);
const DENY = env('DENY_PORTS', '').split(',').map(s => s.trim()).filter(Boolean).map(Number);
const TIMEOUT = Number(env('CONNECT_TIMEOUT_MS', '3000'));
const SCAN_START = Number(env('SCAN_START', '1'));
const SCAN_END = Number(env('SCAN_END', '1024'));
const ALERT_ON_OPEN_PORTS = env('ALERT_ON_OPEN_PORTS', 'true').toLowerCase() === 'true';

const validatePort = p => Number.isInteger(p) && p > 0 && p <= 65535;
const sanitizeStepSegment = value => value.replaceAll(/[^a-zA-Z0-9_-]/g, '-');

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
  const ports = [];

  for (let port = start; port <= end; port++) {
    ports.push(port);
  }

  for (let index = 0; index < ports.length; index += SCAN_CONCURRENCY) {
    const batch = ports.slice(index, index + SCAN_CONCURRENCY);
    const results = await Promise.all(batch.map(async port => {
      const ok = await tryConnect(host, port, timeoutMs);
      return ok ? port : null;
    }));

    openPorts.push(...results.filter(port => port !== null));
  }

  return openPorts;
}

function buildTargetSummary(targetIp, allowedPorts, deniedPorts, unexpectedOpenPorts, summaryOpenPorts) {
  return {
    destIp: targetIp,
    scan: { range: { start: SCAN_START, end: SCAN_END }, openPorts: summaryOpenPorts },
    allowedPorts,
    deniedPorts,
    unexpectedOpenPorts,
    alertOnOpenPorts: ALERT_ON_OPEN_PORTS,
    timestamp: new Date().toISOString()
  };
}

function queueAllowChecks(targetIp, allowedPorts, checks) {
  for (const port of allowedPorts) {
    checks.push(synthetics.executeStep(`tcp-allow-${sanitizeStepSegment(targetIp)}-${port}`, async () => {
      const ok = await tryConnect(targetIp, port, TIMEOUT);
      log.info(`ALLOW check: ${targetIp}:${port} -> ${ok ? 'CONNECTED' : 'FAILED'}`);
      if (!ok) throw new Error(`Expected ALLOW, but could not connect to ${targetIp}:${port}`);
    }));
  }
}

function queueDenyChecks(targetIp, deniedPorts, checks) {
  for (const port of deniedPorts) {
    checks.push(synthetics.executeStep(`tcp-deny-${sanitizeStepSegment(targetIp)}-${port}`, async () => {
      const ok = await tryConnect(targetIp, port, TIMEOUT);
      log.info(`DENY check: ${targetIp}:${port} -> ${ok ? 'CONNECTED' : 'BLOCKED'}`);
      if (ok) throw new Error(`Expected DENY, but connection to ${targetIp}:${port} succeeded`);
    }));
  }
}

async function resolveAllowedPorts(targetIp, baseAllowedPorts, deniedPorts, scanFailures) {
  let allowedPorts = [...baseAllowedPorts];
  let summaryOpenPorts = [];
  let unexpectedOpenPorts = [];
  let scanned = false;

  if (allowedPorts.length > 0) {
    return { allowedPorts, summaryOpenPorts, unexpectedOpenPorts, scanned };
  }

  scanned = true;
  log.info(`ALLOW_PORTS not provided. Scanning ${targetIp} ports ${SCAN_START}-${SCAN_END}...`);
  const openPorts = await scanPorts(targetIp, SCAN_START, SCAN_END);
  summaryOpenPorts = openPorts.slice();

  if (openPorts.length === 0) {
    log.info(`Firewall DENY rule active for ${targetIp}: all scanned ports are blocked.`);
    return { allowedPorts, summaryOpenPorts, unexpectedOpenPorts, scanned };
  }

  unexpectedOpenPorts = openPorts.slice();
  log.info('Summary (pre-alert): ' + JSON.stringify(
    buildTargetSummary(targetIp, allowedPorts, deniedPorts, unexpectedOpenPorts, summaryOpenPorts)
  ));

  if (ALERT_ON_OPEN_PORTS) {
    const failure = `Firewall DENY rule violation for ${targetIp}: unexpected open ports found (${openPorts.join(', ')})`;
    log.error(failure);
    scanFailures.push(failure);
    return { allowedPorts, summaryOpenPorts, unexpectedOpenPorts, scanned };
  }

  log.warn(`Unexpected open ports detected for ${targetIp} (no alert mode): ${openPorts.join(', ')}`);
  allowedPorts = openPorts.filter(port => !deniedPorts.includes(port));
  return { allowedPorts, summaryOpenPorts, unexpectedOpenPorts, scanned };
}

async function evaluateTarget(targetIp, baseAllowedPorts, deniedPorts, checks, scanFailures) {
  const {
    allowedPorts,
    summaryOpenPorts,
    unexpectedOpenPorts,
    scanned
  } = await resolveAllowedPorts(targetIp, baseAllowedPorts, deniedPorts, scanFailures);

  queueAllowChecks(targetIp, allowedPorts, checks);
  queueDenyChecks(targetIp, deniedPorts, checks);

  return {
    destIp: targetIp,
    scan: scanned ? { range: { start: SCAN_START, end: SCAN_END }, openPorts: summaryOpenPorts } : null,
    allowedPorts,
    deniedPorts,
    unexpectedOpenPorts
  };
}

exports.handler = async () => {
  if (TARGET_IPS.length === 0) {
    throw new Error('TARGET_IPS environment variable is required');
  }

  const baseAllowedPorts = ALLOW.filter(validatePort);
  const deniedPorts = DENY.filter(validatePort);
  const checks = [];
  const scanFailures = [];
  const targetResults = [];

  for (const targetIp of TARGET_IPS) {
    targetResults.push(await evaluateTarget(targetIp, baseAllowedPorts, deniedPorts, checks, scanFailures));
  }

  await Promise.all(checks);

  if (scanFailures.length > 0) {
    throw new Error(scanFailures.join('; ') || 'Unexpected open ports detected during scan.');
  }

  // Final JSON summary report
  const summary = {
    targetResults,
    alertOnOpenPorts: ALERT_ON_OPEN_PORTS,
    timestamp: new Date().toISOString()
  };

  log.info('Summary: ' + JSON.stringify(summary));
};