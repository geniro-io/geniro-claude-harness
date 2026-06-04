#!/usr/bin/env node
// geniro-statusline.js — StatusLine hook
// Two rows:
//   line 1 (identity + intent):  update | model·effort | task | session-theme | PR
//   line 2 (location + resources): dir | context | 5h rate-limit | cost
// Every segment except model/dir/context is conditional — it renders only when
// the matching field is present in the stdin JSON, so the bar stays compact on a
// fresh session and grows only when there is something to show.

const fs = require('fs');
const path = require('path');
const os = require('os');

const CACHE_FILE = path.join(process.env.CLAUDE_CONFIG_DIR || path.join(os.homedir(), '.claude'), 'cache', 'geniro-update-check.json');

// ── small helpers ─────────────────────────────────────────────────────────
const DIM = (s) => `\x1b[2m${s}\x1b[0m`;
const COL = (code, s) => `\x1b[${code}m${s}\x1b[0m`;

// Collapse whitespace and clip to n chars with an ellipsis.
function clip(s, n) {
  s = String(s).replace(/\s+/g, ' ').trim();
  return s.length > n ? s.slice(0, n - 1) + '…' : s;
}

// ── palette ──────────────────────────────────────────────────────────────
// Model wears a signature colour per family so the active tier is recognizable
// at a glance; bold to anchor the left edge.
function modelColor(name) {
  const n = name.toLowerCase();
  if (n.includes('opus')) return '1;38;5;141';   // purple
  if (n.includes('sonnet')) return '1;38;5;75';  // sky blue
  if (n.includes('haiku')) return '1;38;5;114';  // green
  return '1;38;5;245';                            // gray
}

// Reasoning effort is graded low→max so a higher (slower, pricier) setting reads
// hotter — the same green→red semantics the context bar and rate-limit use.
function effortColor(level) {
  return ({ low: '38;5;245', medium: '38;5;250', high: '38;5;179', xhigh: '38;5;208', max: '38;5;203' })[level] || '38;5;245';
}

const DIR_COLOR = '38;5;44'; // teal — "where you are"

// Full model name. Prefer display_name when it already carries a version (a
// digit), else reconstruct a friendly label from the id so the full name shows
// even on clients that send a bare family word, e.g.
// "claude-opus-4-8[1m]" → "Opus 4.8 (1M context)".
function modelLabel(m) {
  const dn = m?.display_name;
  if (dn && /\d/.test(dn)) return dn;
  let s = (m?.id || '').replace(/^claude-/, '');
  let ctx = '';
  const mb = s.match(/\[([^\]]+)\]$/);
  if (mb) { ctx = mb[1]; s = s.slice(0, mb.index); }
  const parts = s.split('-').filter(Boolean);
  const family = parts.shift() || '';
  const ver = parts.filter((p) => /^\d{1,2}$/.test(p)).join('.');
  let label = family ? family.charAt(0).toUpperCase() + family.slice(1) : '';
  if (ver) label += ' ' + ver;
  if (ctx) label += ` (${ctx.toUpperCase().replace(/^(\d+)M$/, '$1M context')})`;
  return label || dn || 'Claude';
}

// Short relative ETA from a delta in seconds (e.g. "1h2m", "12m", "now").
function fmtEta(sec) {
  if (sec <= 0) return 'now';
  const m = Math.floor(sec / 60);
  const h = Math.floor(m / 60);
  return h > 0 ? `${h}h${m % 60}m` : `${m}m`;
}

// ── alignment ───────────────────────────────────────────────────────────────
// "East Asian Ambiguous" glyphs we actually render — em/en dash, ellipsis, the
// reset arrow, the box-drawing separator. Some terminals/fonts draw these
// double-width (an over-wide line then gets its right edge truncated by Claude
// Code, e.g. "$137.81" → "$1…"). Charging them 2 is the safe direction: on a
// terminal that draws them narrow the line just under-fills by a column or two
// (a harmless right gap) instead of overflowing.
const AMBIGUOUS_WIDE = new Set([0x2013, 0x2014, 0x2026, 0x21BB, 0x2502]);

// Visible (terminal-column) width of a string: strip ANSI, count code points,
// charging 2 columns for wide glyphs (emoji, CJK, fullwidth, ambiguous-wide).
function visLen(s) {
  const plain = s.replace(/\x1b\[[0-9;]*m/g, '');
  let w = 0;
  for (const ch of plain) {
    const cp = ch.codePointAt(0);
    const wide = cp >= 0x1F000
      || (cp >= 0x1100 && cp <= 0x115F)
      || (cp >= 0x2E80 && cp <= 0xA4CF)
      || (cp >= 0xAC00 && cp <= 0xD7A3)
      || (cp >= 0xF900 && cp <= 0xFAFF)
      || (cp >= 0xFF00 && cp <= 0xFF60)
      || AMBIGUOUS_WIDE.has(cp);
    w += wide ? 2 : 1;
  }
  return w;
}

const spaces = (n) => (n > 0 ? ' '.repeat(n) : '');

// left … right, stretched to width W. Falls back to a single space when there
// is no room, so a too-narrow window degrades to a plain join instead of a gap.
function justify(left, right, W) {
  if (!right) return left;
  const gap = W - visLen(left) - visLen(right);
  return gap < 1 ? `${left} ${right}` : left + spaces(gap) + right;
}

// left … [center] … right, with center centered across W. When the three
// pieces cannot fit with the center centered, the center collapses onto the
// left group and the line is justified left/right instead.
function justify3(left, center, right, W) {
  if (!center) return justify(left, right, W);
  const lw = visLen(left), cw = visLen(center), rw = visLen(right);
  if (lw + cw + rw + 2 > W) return justify(`${left} │ ${center}`, right, W);
  let cStart = Math.floor((W - cw) / 2);
  if (cStart < lw + 1) cStart = lw + 1;
  if (cStart + cw > W - rw - 1) cStart = W - rw - 1 - cw;
  return left + spaces(cStart - lw) + center + spaces(W - rw - (cStart + cw)) + right;
}

// Session theme: prefer the AI-generated title, fall back to the last prompt.
// Reads only the tail of the transcript (last 256KB) so a multi-MB transcript
// does not slow down every status-line render. Partial first line is skipped
// by the per-line try/catch.
function getSessionInfo(transcriptPath) {
  const out = { title: '', lastPrompt: '' };
  try {
    if (!transcriptPath || !fs.existsSync(transcriptPath)) return out;
    const fd = fs.openSync(transcriptPath, 'r');
    const size = fs.fstatSync(fd).size;
    const len = Math.min(size, 262144);
    const buf = Buffer.alloc(len);
    fs.readSync(fd, buf, 0, len, size - len);
    fs.closeSync(fd);
    const lines = buf.toString('utf8').split('\n');
    for (let i = lines.length - 1; i >= 0; i--) {
      const ln = lines[i];
      if (!ln) continue;
      if (!out.title && ln.indexOf('"ai-title"') !== -1) {
        try { const o = JSON.parse(ln); if (o.type === 'ai-title' && o.aiTitle) out.title = o.aiTitle; } catch {}
      }
      if (!out.lastPrompt && ln.indexOf('"last-prompt"') !== -1) {
        try { const o = JSON.parse(ln); if (o.type === 'last-prompt' && o.lastPrompt) out.lastPrompt = o.lastPrompt; } catch {}
      }
      if (out.title && out.lastPrompt) break; // both found; stop at the most recent of each
    }
  } catch {}
  return out;
}

let input = '';
const stdinTimeout = setTimeout(() => process.exit(0), 3000);
process.stdin.setEncoding('utf8');
process.stdin.on('data', (chunk) => { input += chunk; });
process.stdin.on('end', () => {
  clearTimeout(stdinTimeout);
  try {
    const data = JSON.parse(input);
    const model = modelLabel(data.model);
    const dir = data.workspace?.current_dir || process.cwd();
    const remaining = data.context_window?.remaining_percentage;

    // Update notification
    let updateSeg = '';
    try {
      const cache = JSON.parse(fs.readFileSync(CACHE_FILE, 'utf8'));
      if (cache && cache.update_available) {
        const to = cache.latest || '?';
        updateSeg = `\x1b[33m⬆ ${to} /geniro:update\x1b[0m`;
      }
    } catch {}

    // Model (family colour) + reasoning effort (graded low→max; ultracode = xhigh),
    // set off by a spaced dash so the effort reads as a distinct chip.
    const effort = data.effort?.level;
    const modelSeg = COL(modelColor(model), model)
      + (effort ? DIM('  —  ') + COL(effortColor(effort), effort) : '');

    // Context bar with the token count embedded inside it. A colored background
    // sweeps left→right with usage; the centered "usedk/totalk" label rides on
    // top (dark text over the filled span, gray over the empty span); the % sits
    // just after. Normalized to usable context (auto-compact buffer reserved).
    const AUTO_COMPACT_BUFFER_PCT = 16.5;
    let ctx = '';
    if (remaining != null) {
      const usableRemaining = Math.max(0, ((remaining - AUTO_COMPACT_BUFFER_PCT) / (100 - AUTO_COMPACT_BUFFER_PCT)) * 100);
      const used = Math.max(0, Math.min(100, Math.round(100 - usableRemaining)));
      const ctxSize = data.context_window?.context_window_size;
      const usedTokens = ctxSize ? Math.round(ctxSize * used / 100) : null;
      const k = (n) => `${Math.round(n / 1000)}k`;
      const haveTokens = usedTokens != null && ctxSize;
      const label = haveTokens ? `${k(usedTokens)}/${k(ctxSize)}` : `${used}%`;

      // Fill color by usage; blink the background past the danger line (>80%).
      let fillBg = '48;5;34', fg = '38;5;34', blink = '';
      if (used >= 80) { fillBg = '48;5;196'; fg = '38;5;196'; blink = '5;'; }
      else if (used >= 65) { fillBg = '48;5;208'; fg = '38;5;208'; }
      else if (used >= 50) { fillBg = '48;5;178'; fg = '38;5;178'; }

      const W = Math.max(16, label.length + 2);
      const filled = Math.max(0, Math.min(W, Math.round((used / 100) * W)));
      const lpad = Math.floor((W - label.length) / 2);
      const cells = ' '.repeat(lpad) + label + ' '.repeat(W - label.length - lpad);
      const bar = `\x1b[${blink}${fillBg};38;5;232m${cells.slice(0, filled)}\x1b[0m`
        + `\x1b[48;5;236;38;5;250m${cells.slice(filled)}\x1b[0m`;
      ctx = haveTokens ? ` ${bar} ${COL(fg, used + '%')}` : ` ${bar}`;
    }

    // Current task from todos (in-progress activeForm)
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

    // Session context from the transcript: the AI title (the session topic, line
    // 1 centre) and the most recent user prompt (line 2 centre). The PR badge is
    // intentionally not rendered — Claude Code already shows the PR in its own
    // bottom row, so a second copy here would just duplicate it.
    const info = getSessionInfo(data.transcript_path);
    const topic = info.title || info.lastPrompt;
    const lastMsg = (info.lastPrompt && info.lastPrompt !== topic) ? info.lastPrompt : '';

    // 5-hour rate-limit usage + reset countdown
    let rlSeg = '';
    const rl = data.rate_limits?.five_hour;
    if (rl && rl.used_percentage != null) {
      const p = Math.round(rl.used_percentage);
      const code = p < 70 ? '32' : (p < 90 ? '33' : '31');
      let eta = '';
      if (rl.resets_at) {
        const r = Math.max(0, rl.resets_at - Math.floor(Date.now() / 1000));
        eta = ` ↻${fmtEta(r)}`;
      }
      rlSeg = COL(code, `5h ${p}%${eta}`);
    }

    // Session cost
    let costSeg = '';
    const cost = data.cost;
    if (cost && cost.total_cost_usd > 0) costSeg = DIM(`$${cost.total_cost_usd.toFixed(2)}`);

    // Output — two rows, each justified across the terminal width:
    //   line 1: [model — effort · task]  …  «session topic»  …  [5h limit · cost · update]
    //   line 2: [dir · context]  …  «last user message»
    // Claude Code exports COLUMNS before running the script (v2.1.153+). When it
    // is absent or the window is too narrow to justify, fall back to a plain
    // `│`-separated join so older clients and slim terminals still read cleanly.
    const dirname = path.basename(dir);

    const l1left = [modelSeg, task ? `\x1b[1m${task}\x1b[0m` : '']
      .filter(Boolean).join(' │ ');
    const l1center = (topic && topic !== task) ? DIM(clip(topic, 40)) : '';
    const l1right = [rlSeg, costSeg, updateSeg].filter(Boolean).join(' │ ');

    const l2left = `${COL(DIR_COLOR, dirname)}${ctx}`;
    const l2center = lastMsg ? DIM(clip(lastMsg, 50)) : '';

    const W = parseInt(process.env.COLUMNS || '', 10);
    let out;
    if (W && W >= 40) {
      // Justify two columns short of the edge: Claude Code keeps a little
      // horizontal padding around the status line, so filling to exactly COLUMNS
      // would push the rightmost segment past the visible area and truncate it
      // ("$137.81" → "$1…"). visLen already accounts for ambiguous-wide glyphs;
      // this margin covers the UI chrome.
      const Wj = W - 2;
      out = justify3(l1left, l1center, l1right, Wj) + '\n' + justify3(l2left, l2center, '', Wj);
    } else {
      const a = [l1left, l1center, l1right].filter(Boolean).join(' │ ');
      const b = [l2left, l2center].filter(Boolean).join(' │ ');
      out = a + '\n' + b;
    }
    process.stdout.write(out);
  } catch {
    process.stdout.write('geniro');
  }
});
