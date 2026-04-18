#!/usr/bin/env node
// geniro-statusline.js — StatusLine hook
// Shows: update notification | model | current task | directory | context usage

const fs = require('fs');
const path = require('path');
const os = require('os');

const CACHE_FILE = path.join(os.homedir(), '.claude', 'cache', 'geniro-update-check.json');

let input = '';
const stdinTimeout = setTimeout(() => process.exit(0), 3000);
process.stdin.setEncoding('utf8');
process.stdin.on('data', (chunk) => { input += chunk; });
process.stdin.on('end', () => {
  clearTimeout(stdinTimeout);
  try {
    const data = JSON.parse(input);
    const model = data.model?.display_name || 'Claude';
    const dir = data.workspace?.current_dir || process.cwd();
    const remaining = data.context_window?.remaining_percentage;

    // Update notification
    let update = '';
    try {
      const cache = JSON.parse(fs.readFileSync(CACHE_FILE, 'utf8'));
      if (cache && cache.update_available) {
        const to = cache.latest || '?';
        update = `\x1b[33m\u2B06 ${to} /geniro:update\x1b[0m \u2502 `;
      }
    } catch {}

    // Context window bar (10 segments, normalized to usable context)
    const AUTO_COMPACT_BUFFER_PCT = 16.5;
    let ctx = '';
    if (remaining != null) {
      const usableRemaining = Math.max(0, ((remaining - AUTO_COMPACT_BUFFER_PCT) / (100 - AUTO_COMPACT_BUFFER_PCT)) * 100);
      const used = Math.max(0, Math.min(100, Math.round(100 - usableRemaining)));
      const filled = Math.floor(used / 10);
      const bar = '\u2588'.repeat(filled) + '\u2591'.repeat(10 - filled);

      // Token count (used / total)
      const ctxSize = data.context_window?.context_window_size;
      const usedTokens = ctxSize ? Math.round(ctxSize * used / 100) : null;
      const tokenLabel = usedTokens != null && ctxSize
        ? ` ${(usedTokens / 1000).toFixed(0)}k/${(ctxSize / 1000).toFixed(0)}k`
        : '';

      if (used < 50) {
        ctx = ` \x1b[32m${bar} ${used}%${tokenLabel}\x1b[0m`;
      } else if (used < 65) {
        ctx = ` \x1b[33m${bar} ${used}%${tokenLabel}\x1b[0m`;
      } else if (used < 80) {
        ctx = ` \x1b[38;5;208m${bar} ${used}%${tokenLabel}\x1b[0m`;
      } else {
        ctx = ` \x1b[5;31m\uD83D\uDC80 ${bar} ${used}%${tokenLabel}\x1b[0m`;
      }
    }

    // Current task from todos
    let task = '';
    const claudeDir = process.env.CLAUDE_CONFIG_DIR || path.join(os.homedir(), '.claude');
    const todosDir = path.join(claudeDir, 'todos');
    const session = data.session_id || '';
    if (session && fs.existsSync(todosDir)) {
      try {
        const files = fs.readdirSync(todosDir)
          .filter(f => f.startsWith(session) && f.includes('-agent-') && f.endsWith('.json'))
          .map(f => ({ name: f, mtime: fs.statSync(path.join(todosDir, f)).mtime }))
          .sort((a, b) => b.mtime - a.mtime);
        if (files.length > 0) {
          const todos = JSON.parse(fs.readFileSync(path.join(todosDir, files[0].name), 'utf8'));
          const inProgress = todos.find(t => t.status === 'in_progress');
          if (inProgress) task = inProgress.activeForm || '';
        }
      } catch {}
    }

    // Output
    const dirname = path.basename(dir);
    const parts = [`\x1b[2m${model}\x1b[0m`];
    if (task) parts.push(`\x1b[1m${task}\x1b[0m`);
    parts.push(`\x1b[2m${dirname}\x1b[0m${ctx}`);
    process.stdout.write(update + parts.join(' \u2502 '));
  } catch {
    process.stdout.write('geniro');
  }
});
