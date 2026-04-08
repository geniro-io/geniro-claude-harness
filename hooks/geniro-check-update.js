#!/usr/bin/env node
// geniro-check-update.js — SessionStart hook
// Checks if a newer version of geniro-claude-plugin is available.
// Runs as a detached background process to avoid blocking session start.

const { execSync, spawn } = require('child_process');
const fs = require('fs');
const path = require('path');

// Detach into background on first run
if (!process.env.GENIRO_UPDATE_BG) {
  const child = spawn(process.execPath, [__filename], {
    detached: true,
    stdio: 'ignore',
    env: { ...process.env, GENIRO_UPDATE_BG: '1' }
  });
  child.unref();
  // Consume stdin and exit immediately so Claude Code isn't blocked
  process.stdin.resume();
  process.stdin.on('data', () => {});
  process.stdin.on('end', () => process.exit(0));
  return;
}

const CACHE_DIR = path.join(process.env.HOME || '', '.claude', 'cache');
const CACHE_FILE = path.join(CACHE_DIR, 'geniro-update-check.json');
const CHECK_INTERVAL_MS = 6 * 60 * 60 * 1000; // 6 hours

function readCache() {
  try {
    return JSON.parse(fs.readFileSync(CACHE_FILE, 'utf8'));
  } catch { return null; }
}

function writeCache(data) {
  try {
    fs.mkdirSync(CACHE_DIR, { recursive: true });
    fs.writeFileSync(CACHE_FILE, JSON.stringify(data, null, 2));
  } catch {}
}

function getInstalledVersion() {
  // Read from plugin.json in the plugin root
  const pluginRoot = process.env.CLAUDE_PLUGIN_ROOT || path.resolve(__dirname, '..');
  try {
    const manifest = JSON.parse(fs.readFileSync(path.join(pluginRoot, '.claude-plugin', 'plugin.json'), 'utf8'));
    return manifest.version || 'unknown';
  } catch { return 'unknown'; }
}

function getLatestVersion() {
  try {
    // Check the GitHub API for the latest release tag
    const result = execSync(
      'curl -sf --max-time 10 "https://api.github.com/repos/geniro-io/geniro-claude-harness/releases/latest"',
      { encoding: 'utf8', timeout: 15000 }
    );
    const data = JSON.parse(result);
    return (data.tag_name || '').replace(/^v/, '') || null;
  } catch {
    // Fallback: check package.json or plugin.json from main branch
    try {
      const result = execSync(
        'curl -sf --max-time 10 "https://raw.githubusercontent.com/geniro-io/geniro-claude-harness/main/.claude-plugin/plugin.json"',
        { encoding: 'utf8', timeout: 15000 }
      );
      const data = JSON.parse(result);
      return data.version || null;
    } catch { return null; }
  }
}

function compareVersions(a, b) {
  if (!a || !b || a === 'unknown') return false;
  const pa = a.split('.').map(Number);
  const pb = b.split('.').map(Number);
  for (let i = 0; i < 3; i++) {
    if ((pb[i] || 0) > (pa[i] || 0)) return true;
    if ((pb[i] || 0) < (pa[i] || 0)) return false;
  }
  return false;
}

// Skip if recently checked
const cached = readCache();
if (cached && cached.checked && (Date.now() - cached.checked) < CHECK_INTERVAL_MS) {
  process.exit(0);
}

const installed = getInstalledVersion();
const latest = getLatestVersion();

if (latest) {
  const updateAvailable = compareVersions(installed, latest);
  writeCache({
    update_available: updateAvailable,
    installed,
    latest,
    checked: Date.now()
  });
}

process.exit(0);
