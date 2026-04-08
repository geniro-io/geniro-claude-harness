#!/usr/bin/env node
// geniro-statusline.js — StatusLine hook
// Outputs a status line for Claude Code. Shows update notification if available.

const fs = require('fs');
const path = require('path');

const CACHE_FILE = path.join(process.env.HOME || '', '.claude', 'cache', 'geniro-update-check.json');

// Read stdin with a timeout to prevent hangs
let input = '';
const timeout = setTimeout(() => {
  output();
}, 3000);

process.stdin.setEncoding('utf8');
process.stdin.on('data', (chunk) => { input += chunk; });
process.stdin.on('end', () => {
  clearTimeout(timeout);
  output();
});

function output() {
  let updateAvailable = false;
  try {
    const cache = JSON.parse(fs.readFileSync(CACHE_FILE, 'utf8'));
    if (cache && cache.update_available) {
      updateAvailable = true;
    }
  } catch {
    // Cache doesn't exist or is invalid — ignore
  }

  if (updateAvailable) {
    process.stdout.write('\x1b[33m\u2B06 /geniro:update\x1b[0m | geniro');
  } else {
    process.stdout.write('geniro');
  }
  process.exit(0);
}
