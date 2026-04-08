#!/usr/bin/env node
// geniro-statusline.js — statusLine hook
// Displays geniro-claude-plugin status in Claude Code's status bar.
// Shows update availability when a newer version is detected.

const fs = require('fs');
const path = require('path');

const CACHE_FILE = path.join(process.env.HOME || '', '.claude', 'cache', 'geniro-update-check.json');

// Consume stdin (required for hooks)
let input = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (chunk) => { input += chunk; });
process.stdin.on('end', () => {
  const parts = [];

  // Check for update notification
  try {
    const cache = JSON.parse(fs.readFileSync(CACHE_FILE, 'utf8'));
    if (cache.update_available) {
      parts.push('\x1b[33m\u2B06 /geniro:update\x1b[0m');
    }
  } catch {}

  // Add geniro identifier
  parts.push('geniro');

  process.stdout.write(parts.join(' \u2502 '));
  process.exit(0);
});
