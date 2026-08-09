#!/usr/bin/env python3
"""find-threads scan engine.

Enumerate work-bearing Claude session logs across every config-dir root — threads that
edited code, ran a skill, or spawned a subagent — optionally filter + rank them by a
content query, and print one tab-separated row per surviving thread.

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
  3. $FIND_THREADS_EXTRA_ROOTS          (colon-separated extra config dirs; EXTRA_ROOTS below is
                                         the default used when the var is unset)

Usage:
  python3 scan.py                 # list mode: every work-bearing thread (edited + read-only), grouped-sort
  python3 scan.py <query...>      # search mode: keep threads matching the query, ranked best-first
  python3 scan.py --code-only     # restrict to code-editing threads (the legacy behavior); combines with a query

Query matching (see _term_positions):
  - issue key (ENG-317 / ENG317):   separator-insensitive — both spellings find the canonical `eng-317`.
  - bare 3-6 digit number (2649): read as a PR reference (pull/2649, #2649, pr-2649), so it ignores
                                  the same digits inside UUIDs / token counts; raw-number fallback only
                                  when the thread has no PR-style reference at all.
  - anything else:                literal substring, lowercased.
  Multiple terms are OR-matched and ranked by how tightly they co-occur, so a multi-term query
  (`ENG-315 ENG-316 case_table`) unions a whole feature's threads — a single ticket key only finds threads
  that name it, missing the sibling-ticket and feature-named work that makes up the rest of the epic.

Output columns (TSV):
  mtime  date  oversize  kind  turns  relevance  hits  label  title  path  snippet
    - kind: "edited" (calls a code-edit tool) | "read-only" (spawns a subagent / invokes a Skill but never edits code).
    - turns: user+assistant events in the scanned head; a trailing "+" means the file outran the
             12 MB read cap, so the count is a floor rather than a total.
    - list mode:   relevance=0, hits=0, snippet="" ; sorted by label asc, then newest-first.
    - search mode: relevance = the most query terms that co-occur in one ~160-char window (the
                   proximity score) ; hits = total term occurrences ; a thread is kept only when the
                   query matches its body, title, or label ; sorted relevance desc, hits desc, newest.

A "#SUMMARY threads=N projects=M edited=E read-only=R" line goes to stderr, so a consumer piping the
TSV never has to filter a non-row line out of the stream.
"""
import sys, os, re, json, glob, time

# --- Extra config-dir roots, for a second Claude config dir that the CLAUDE_CONFIG_DIR env var is
# NOT exporting into this session. Export FIND_THREADS_EXTRA_ROOTS as a colon-separated list of
# "<config-dir>/projects" paths, or list them (one per line, # comments allowed) in the
# machine-local, gitignored roots.local next to this script — committed code stays free of
# machine paths. "~" is expanded in roots().
_LOCAL_ROOTS_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "roots.local")

def _local_roots():
    try:
        with open(_LOCAL_ROOTS_FILE) as f:
            return [l.strip() for l in f if l.strip() and not l.startswith("#")]
    except OSError:
        return []

EXTRA_ROOTS = [p for p in os.environ.get("FIND_THREADS_EXTRA_ROOTS", "").split(":") if p.strip()] or _local_roots()

CODE_SIGNAL = re.compile(r'"name":"(?:Edit|Write|MultiEdit|NotebookEdit)"')
WORK_SIGNAL = re.compile(r'"name":"(?:Agent|Task|Skill)"')  # read-only agentic work: a spawned subagent or a Skill tool call
OVERSIZE_BYTES = 5 * 1024 * 1024          # /analyze-thread's hard cap
SIGNAL_SCAN_CAP = 20 * 1024 * 1024        # scan at most 20 MB for the work signals
TITLE_SCAN_CAP = 2 * 1024 * 1024          # window into the head read for the ai-title line (~1.5 MB deep)
PROMPT_SCAN_CAP = 800 * 1024              # window for the first real user prompt (opening events)
SEARCH_SCAN_CAP = 12 * 1024 * 1024        # size of the ONE head read per file — feeds label, title, turns, search


def roots():
    out, seen = [], set()
    cands = ["~/.claude/projects"]
    cfg = os.environ.get("CLAUDE_CONFIG_DIR", "").strip()
    if cfg:
        cands.append(os.path.join(cfg, "projects"))
    cands.extend(EXTRA_ROOTS)
    for c in cands:
        c = os.path.realpath(os.path.expanduser(c))
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


def classify_thread(path, size):
    # Return the thread's kind: "edited" (calls a code-edit tool), "read-only" (spawns a
    # subagent or invokes a Skill but never edits code), or None (neither — trivial chat, dropped).
    # A code-edit short-circuits ("edited" dominates); "read-only" is declared only after the full
    # cap scan finds no edit, so an editing thread is never mislabelled read-only because a spawn
    # happened to appear first.
    cap = min(size, SIGNAL_SCAN_CAP)
    work = False
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
                    return "edited"
                if not work and WORK_SIGNAL.search(text):
                    work = True
                tail = text[-64:]  # carry a boundary so a split signal still matches
    except OSError:
        return None
    return "read-only" if work else None


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


# label_of / title_of / turns_of / search_score all take the ONE head read main() does per file.
# Re-opening the file per helper cost up to 16.8 MB of redundant reads and UTF-8 decodes per thread.
# The narrower caps are character windows into that blob; a decoded character is never fewer than one
# byte, so each window still covers at least the byte budget it used to read.


def label_of(blob, path):
    # True project label = first parseable .cwd. The first line literally containing "cwd" is
    # sometimes a base64 blob whose bytes spell it; that line fails to parse, so parse each line.
    for ln in blob[:TITLE_SCAN_CAP].splitlines():
        try:
            o = json.loads(ln)
        except (ValueError, TypeError):
            continue
        cwd = o.get("cwd")
        if cwd:
            return cwd
    return os.path.basename(os.path.dirname(path))  # lossy folder-name fallback


def title_of(blob):
    for ln in blob[:TITLE_SCAN_CAP].splitlines():
        if '"type":"ai-title"' in ln:
            try:
                o = json.loads(ln)
            except (ValueError, TypeError):
                continue
            at = o.get("aiTitle")
            if at:
                return at[:100]
    head = blob[:PROMPT_SCAN_CAP]
    skip = ("<command-", "<local-command-", "Base directory for this skill:", "Caveat: The messages below")
    for t in iter_user_texts(head):
        if not any(s in t[:40] for s in skip):
            return t[:100]
    m = re.search(r"<command-name>([^<]+)</command-name>", head)
    if m:
        return m.group(1).strip()[:100]
    return "(thread — no title)"


def turns_of(blob):
    # Counts only what the head read covers; main() marks the count "+" when the file is bigger.
    return sum(1 for ln in blob.splitlines()
               if '"type":"user"' in ln or '"type":"assistant"' in ln)


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
ISSUE_KEY = re.compile(r"^([a-z]{2,})[-_ ]?(\d+)$")  # Linear/Jira key: ENG-317, ENG317, abc-1234


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
    # An issue-key term matches separator-insensitively: a query typed `ENG317` (or `ENG 317`) still
    # finds the canonical hyphenated `eng-317` spelling, and vice versa. Without this the literal
    # `eng317` never matches a body that only ever writes `eng-317`, so the whole ticket's work is
    # invisible — the failure that hid an entire epic. The leading boundary keeps the key from
    # matching inside a base64 blob or a longer id (the source of phantom single-hit matches).
    m = ISSUE_KEY.match(term)
    if m:
        pat = re.compile(r"(?<![a-z0-9])" + re.escape(m.group(1)) + r"[-_ ]?" + m.group(2) + r"(?!\d)")
        return [mm.start() for mm in pat.finditer(low)]
    return _positions(low, term)


def search_score(blob, terms):
    """Score a thread against the query.

    Returns (relevance, total_hits, snippet):
      relevance  = the most query terms that co-occur inside one ~160-char window. Threads where
                   the terms cluster (a real topical match) outrank threads where a common word
                   like "post" merely appears scattered among unrelated JSON.
      total_hits = total term occurrences (a tie-breaker within a relevance tier).
      snippet    = cleaned text around the densest window, for disambiguation in the list.
    """
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
    # --code-only is a flag, not a search term; everything else is a query term.
    code_only = "--code-only" in sys.argv[1:]
    terms = [a.lower() for a in sys.argv[1:] if a.strip() and a != "--code-only"]
    rows = []
    for root in roots():
        for path in glob.glob(os.path.join(root, "*", "*.jsonl")):
            try:
                st = os.stat(path)
            except OSError:
                continue
            kind = classify_thread(path, st.st_size)
            if kind is None:
                continue
            if code_only and kind != "edited":
                continue
            mtime = int(st.st_mtime)
            blob = read_head(path, SEARCH_SCAN_CAP)   # the one read every helper below shares
            label = " ".join(label_of(blob, path).split())
            title = " ".join(title_of(blob).split())[:100]
            relevance = hits = 0
            snippet = ""
            if terms:
                relevance, hits, snippet = search_score(blob, terms)
                meta = (label + " " + title).lower()
                in_meta = any(t in meta for t in terms)
                if relevance == 0 and not in_meta:
                    continue  # no term matched the body, title, or label → drop
                if in_meta:
                    relevance = max(relevance, 1)  # a title/label hit is at least one matched surface
            date = time.strftime("%Y-%m-%d", time.localtime(mtime))
            oversize = 1 if st.st_size > OVERSIZE_BYTES else 0
            turns = turns_of(blob)
            if st.st_size > SEARCH_SCAN_CAP:
                turns = "%d+" % turns      # scan capped — the printed count is a floor, not a total
            rows.append((mtime, date, oversize, kind, turns, relevance, hits, label, title, path, snippet))

    if terms:
        rows.sort(key=lambda r: (-r[5], -r[6], -r[0]))   # relevance desc, hits desc, newest
    else:
        rows.sort(key=lambda r: (r[7], -r[0]))           # label asc, newest-first

    # Aggregates the caller would otherwise tally by eye. stderr, so a consumer piping the TSV
    # (analyze-thread's batch scan) never has to filter a non-row line out of the stream.
    edited = sum(1 for r in rows if r[3] == "edited")
    print("#SUMMARY threads=%d projects=%d edited=%d read-only=%d"
          % (len(rows), len({r[7] for r in rows}), edited, len(rows) - edited), file=sys.stderr)

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
