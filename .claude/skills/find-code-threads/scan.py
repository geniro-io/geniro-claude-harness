#!/usr/bin/env python3
"""find-code-threads scan engine.

Enumerate code-bearing Claude session logs across every config-dir root, optionally
filter + rank them by a content query, and print one tab-separated row per surviving thread.

Why Python and not a shell pipeline:
  - grep skips .jsonl logs that embed base64 images as "binary" unless forced (-a); a single
    read+search in Python never silently drops them.
  - the macOS zsh sandbox strips PATH inside `| while` / `for in $(...)` loop bodies, so a
    per-file shell loop loses `cut`/`head`/`awk` mid-run. One process has no inner loops to break.
  - content ranking (per-term hit counts + a disambiguation snippet) is trivial in Python and
    painful in shell.

Roots scanned (a thread's session logs live under <config-dir>/projects/):
  1. ~/.claude/projects                 (default config dir)
  2. $CLAUDE_CONFIG_DIR/projects        (when the env var is set and the dir exists)
  3. every path in EXTRA_ROOTS below    (fixed extra config dirs — add yours here)

Usage:
  python3 scan.py                 # list mode: every code-bearing thread, grouped-sort
  python3 scan.py <query...>      # search mode: keep threads matching the query, ranked best-first

Output columns (TSV):
  mtime  date  oversize  turns  relevance  hits  label  title  path  snippet
    - list mode:   relevance=0, hits=0, snippet="" ; sorted by label asc, then newest-first.
    - search mode: relevance = the most query terms that co-occur in one ~160-char window (the
                   proximity score) ; hits = total term occurrences ; a thread is kept only when the
                   query matches its body, title, or label ; sorted relevance desc, hits desc, newest.
"""
import sys, os, re, json, glob, time

# --- Fixed extra config-dir roots. The default + $CLAUDE_CONFIG_DIR are added automatically. ---
# Add one absolute "<config-dir>/projects" path per entry when you run a second Claude config dir
# that the CLAUDE_CONFIG_DIR env var is NOT exporting into this session's environment.
EXTRA_ROOTS = [
    os.path.expanduser("~/Desktop/Projects/ManifestLab/.claude-manifest-lab/projects"),
]

CODE_SIGNAL = re.compile(r'"name":"(?:Edit|Write|MultiEdit|NotebookEdit)"')
OVERSIZE_BYTES = 5 * 1024 * 1024          # /analyze-thread's hard cap
SIGNAL_SCAN_CAP = 20 * 1024 * 1024        # scan at most 20 MB for the code-edit signal
TITLE_SCAN_CAP = 2 * 1024 * 1024          # the ai-title line can sit ~1.5 MB deep
PROMPT_SCAN_CAP = 800 * 1024              # first real user prompt lives in the opening events
SEARCH_SCAN_CAP = 12 * 1024 * 1024        # body bytes scanned for query matches (bounds huge logs)


def roots():
    out, seen = [], set()
    cands = [os.path.expanduser("~/.claude/projects")]
    cfg = os.environ.get("CLAUDE_CONFIG_DIR", "").strip()
    if cfg:
        cands.append(os.path.join(os.path.expanduser(cfg), "projects"))
    cands.extend(EXTRA_ROOTS)
    for c in cands:
        c = os.path.realpath(c)
        if c not in seen and os.path.isdir(c):
            seen.add(c)
            out.append(c)
    return out


def read_head(path, n):
    try:
        with open(path, "rb") as fh:
            return fh.read(n).decode("utf-8", "ignore")
    except OSError:
        return ""


def has_code_signal(path, size):
    # Read in chunks, stop at the first edit-tool call (most code threads edit early).
    cap = min(size, SIGNAL_SCAN_CAP)
    try:
        with open(path, "rb") as fh:
            read = 0
            tail = ""
            while read < cap:
                chunk = fh.read(1024 * 256)
                if not chunk:
                    break
                read += len(chunk)
                text = tail + chunk.decode("utf-8", "ignore")
                if CODE_SIGNAL.search(text):
                    return True
                tail = text[-64:]  # carry a boundary so a split signal still matches
    except OSError:
        return False
    return False


def iter_user_texts(blob):
    for ln in blob.splitlines():
        try:
            o = json.loads(ln)
        except (ValueError, TypeError):
            continue
        if o.get("type") != "user":
            continue
        c = o.get("message", {}).get("content")
        if isinstance(c, str):
            t = c
        elif isinstance(c, list):
            t = " ".join(b.get("text", "") for b in c if isinstance(b, dict) and b.get("type") == "text")
        else:
            t = ""
        t = " ".join(t.split())
        if t:
            yield t


def label_of(path):
    # True project label = first parseable .cwd. The first line literally containing "cwd" is
    # sometimes a base64 blob whose bytes spell it; that line fails to parse, so parse each line.
    blob = read_head(path, TITLE_SCAN_CAP)
    for ln in blob.splitlines():
        try:
            o = json.loads(ln)
        except (ValueError, TypeError):
            continue
        cwd = o.get("cwd")
        if cwd:
            return cwd
    return os.path.basename(os.path.dirname(path))  # lossy folder-name fallback


def title_of(path):
    blob = read_head(path, TITLE_SCAN_CAP)
    for ln in blob.splitlines():
        if '"type":"ai-title"' in ln:
            try:
                o = json.loads(ln)
            except (ValueError, TypeError):
                continue
            at = o.get("aiTitle")
            if at:
                return at[:100]
    head = read_head(path, PROMPT_SCAN_CAP)
    skip = ("<command-", "<local-command-", "Base directory for this skill:", "Caveat: The messages below")
    for t in iter_user_texts(head):
        if not any(s in t[:40] for s in skip):
            return t[:100]
    m = re.search(r"<command-name>([^<]+)</command-name>", head)
    if m:
        return m.group(1).strip()[:100]
    return "(code thread — no title)"


def turns_of(path):
    n = 0
    blob = read_head(path, SEARCH_SCAN_CAP)
    for ln in blob.splitlines():
        if '"type":"user"' in ln or '"type":"assistant"' in ln:
            n += 1
    return n


def _positions(low, needle, cap=4000):
    out, start = [], 0
    while len(out) < cap:
        i = low.find(needle, start)
        if i < 0:
            break
        out.append(i)
        start = i + len(needle)
    return out


PR_NUM = re.compile(r"^\d{3,6}$")


def _term_positions(low, term):
    # A bare 3-6 digit term is read as a PR reference (pull/N, #N, pr-N, pr N) so it does not
    # match the same digits buried in UUIDs, token counts, and timestamps. Fall back to the raw
    # number only when the thread has no PR-style reference at all.
    if PR_NUM.match(term):
        pat = re.compile(r"(?:pull/|#|pr[ \-]|pull request )0*" + term + r"(?!\d)")
        pos = [m.start() for m in pat.finditer(low)]
        if pos:
            return pos
    return _positions(low, term)


def search_score(path, terms):
    """Score a thread against the query.

    Returns (relevance, total_hits, snippet):
      relevance  = the most query terms that co-occur inside one ~160-char window. Threads where
                   the terms cluster (a real topical match) outrank threads where a common word
                   like "post" merely appears scattered among unrelated JSON.
      total_hits = total term occurrences (a tie-breaker within a relevance tier).
      snippet    = cleaned text around the densest window, for disambiguation in the list.
    """
    blob = read_head(path, SEARCH_SCAN_CAP)
    low = blob.lower()
    occ, total = [], 0
    for i, t in enumerate(terms):
        ps = _term_positions(low, t)
        total += len(ps)
        for p in ps:
            occ.append((p, i))
    if not occ:
        return 0, 0, ""
    occ.sort()
    WINDOW = 160
    best, best_at, left, seen = 1, occ[0][0], 0, {}
    for right in range(len(occ)):
        pr, ir = occ[right]
        seen[ir] = seen.get(ir, 0) + 1
        while pr - occ[left][0] > WINDOW:
            il = occ[left][1]
            seen[il] -= 1
            if seen[il] == 0:
                del seen[il]
            left += 1
        if len(seen) > best:
            best, best_at = len(seen), occ[left][0]
    raw = blob[max(0, best_at - 40): best_at + 120]
    return best, total, " ".join(raw.split())[:120]


def main():
    terms = [a.lower() for a in sys.argv[1:] if a.strip()]
    rows = []
    for root in roots():
        for path in glob.glob(os.path.join(root, "*", "*.jsonl")):
            try:
                st = os.stat(path)
            except OSError:
                continue
            if not has_code_signal(path, st.st_size):
                continue
            mtime = int(st.st_mtime)
            label = " ".join(label_of(path).split())
            title = " ".join(title_of(path).split())[:100]
            relevance = hits = 0
            snippet = ""
            if terms:
                relevance, hits, snippet = search_score(path, terms)
                meta = (label + " " + title).lower()
                in_meta = any(t in meta for t in terms)
                if relevance == 0 and not in_meta:
                    continue  # no term matched the body, title, or label → drop
                if in_meta:
                    relevance = max(relevance, 1)  # a title/label hit is at least one matched surface
            date = time.strftime("%Y-%m-%d", time.localtime(mtime))
            oversize = 1 if st.st_size > OVERSIZE_BYTES else 0
            turns = turns_of(path)
            rows.append((mtime, date, oversize, turns, relevance, hits, label, title, path, snippet))

    if terms:
        rows.sort(key=lambda r: (-r[4], -r[5], -r[0]))   # relevance desc, hits desc, newest
    else:
        rows.sort(key=lambda r: (r[6], -r[0]))           # label asc, newest-first

    try:
        for r in rows:
            print("\t".join(str(x) for x in r))
        sys.stdout.flush()
    except BrokenPipeError:
        # A downstream `head`/`sed` closed the pipe early — expected, not an error.
        try:
            sys.stdout.close()
        except OSError:
            pass


if __name__ == "__main__":
    try:
        main()
    except BrokenPipeError:
        os._exit(0)
