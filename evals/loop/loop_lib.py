#!/usr/bin/env python3
"""evals/loop scoring library (module-agnostic core).

Subcommands:
  parse   <raw-*.json ...>                 -> findings JSON on stdout
  judgeprompt <rubric.json> <findings.json>  -> judge prompt on stdout
  extract <judge-raw.json>                 -> the judge's JSON verdict on stdout
  vote    <match.json ...>                 -> modal consensus over N judge verdicts
  metrics <task.json> <rubric.json> <findings.json> <match.json> <raw-dir>
                                           -> per-trial metrics JSON on stdout

A rubric is {"version": int, "negative": bool, "items": [...]}; a bare legacy
array is accepted and treated as version 0. Items use the ground-truth schema
(id/file/lines/class/severity/must_find/description), plus an optional
`polarity: "absence"` for an item asserting what the output must NOT claim —
scored by the inverted test, satisfied when nothing matched it.

Five parsers ship: `review-findings` (the /geniro:review §Output Format shape),
`spec-claims` (the spec-challenge per-claim verdict shape), `audit-findings`
(the audit-pipeline reviewer table), `partition-couplings` (the
/geniro:implement Phase 2 file-set partition shape), and `recon-items` (the
/geniro:implement Phase 1 knowledge-retrieval and codebase-explorer report
shapes). A module names the one it needs in its target.json `parser` field; a
new output shape adds a function here and a PARSERS entry.

`recon-items` emits one finding per bullet the Phase 1 recon reports carry, with
the section heading kept in the title. The rubric's items are the things the
reports were required to surface — a governing past learning, a file the change
will touch, the rule that constrains it — so recall_must reads "did Phase 1 hand
the orchestrator what it needed" and noise_strict reads "did it assert something
that is not there". The two axes do NOT cost the same here, which is why this
module's negative_pass_expr drops the plausible_real clause the other modules
carry: an unmatched review finding asserts a defect exists, while an unmatched
recon item only says a file may be relevant — usually true and cheap when wrong.

`spec-claims` emits one finding per claim the run judged WRONG — refuted or
clarified — and none for a confirmed claim. That keeps the rubric on the same
footing as every other module's: its items are the claims that are genuinely
wrong, so recall_must reads "did the pass catch the bad claims" and noise reads
"did it flag good ones", with cmd_metrics unchanged.

`partition-couplings` emits one finding per pair of todos the run declared
COUPLED, and none for the pairs it split into separate delegate groups. The
rubric's items are the couplings that are genuinely there but do not look it, so
recall_must reads "did the partition catch the hidden dependency" and noise
reads "did it call independent work coupled". Both directions cost something
real: a missed coupling puts two delegates in one file, while a phantom one
collapses the partition to a single group and delegation never fires.
"""
import json, re, sys, glob, os, random

SEV_W = {"CRITICAL": 4, "HIGH": 3, "MEDIUM": 2, "LOW": 1}

def load_rubric(path):
    data = json.load(open(path))
    if isinstance(data, list):
        return {"version": 0, "negative": False, "items": data}
    data.setdefault("version", 0)
    data.setdefault("negative", False)
    data.setdefault("items", [])
    return data

def load_result_text(path):
    try:
        with open(path) as f:
            raw = json.load(f)
    except Exception:
        return "", {}, True
    text = raw.get("result") or ""
    usage = raw.get("usage") or {}
    return text, usage, bool(raw.get("is_error"))

FINDING_RE = re.compile(r"^###\s+\[?(CRITICAL|HIGH|MEDIUM|LOW)\]?[:\s]+(.+)$")
FILE_RE = re.compile(r"\*\*File:?\*\*:?\s*`?([^\s`]+?)`?\s*$")
CONF_RE = re.compile(r"\*\*Confidence:?\*\*:?\s*(\d+)")
DT_RE = re.compile(r"\*\*Decision Type:?\*\*:?\s*\[?([A-Z-]+)\]?")
ORIGIN_RE = re.compile(r"\*\*Origin:?\*\*:?\s*\[?(NEW|PRE-EXISTING)\]?")

def parse_file_field(s):
    # path/to/file.ts:42-48 | path:42 | path
    m = re.match(r"^(.*?):(\d+)(?:\s*[-–]\s*(\d+))?$", s)
    if not m:
        return s, None, None
    a = int(m.group(2)); b = int(m.group(3)) if m.group(3) else a
    return m.group(1), a, b

SPEC_CLAIM_RE = re.compile(r"^###\s+\[?(REFUTED|CLARIFIED)\]?[:\s]+(.+)$", re.I)
CITED_RE = re.compile(r"\*\*Cited:?\*\*:?\s*`?([^\s`]+?)`?\s*$")
# A refuted claim is a fact the spec asserts and the code contradicts; a
# clarified one is true-but-mis-framed. Weighted recall needs them ordered, so
# they borrow the severity scale rather than inventing a second one.
CLAIM_SEV = {"REFUTED": "HIGH", "CLARIFIED": "MEDIUM"}

def parse_spec_claims(text, facet):
    blocks = []
    cur = None
    for line in text.splitlines():
        m = SPEC_CLAIM_RE.match(line.strip())
        if m:
            kind = m.group(1).upper()
            cur = {"severity": CLAIM_SEV[kind], "verdict": kind,
                   "title": m.group(2).strip(), "facet": facet,
                   "file": None, "line_start": None, "line_end": None,
                   "confidence": None, "decision_type": None, "origin": None,
                   "has_evidence": False, "body": []}
            blocks.append(cur)
            continue
        if line.startswith("## ") and cur is not None:
            cur = None  # left the verdict region (e.g. Claim Summary)
        if cur is None:
            continue
        cur["body"].append(line)
        cm = CITED_RE.search(line)
        if cm and cur["file"] is None:
            f, a, b = parse_file_field(cm.group(1).strip())
            cur["file"], cur["line_start"], cur["line_end"] = f, a, b
        conf = CONF_RE.search(line)
        if conf: cur["confidence"] = int(conf.group(1))
        if "**Evidence" in line:
            cur["has_evidence"] = True
    return blocks

# The audit skills' reviewers return a Markdown table, not verdict blocks:
# id | tier | file:line | issue | evidence | fix | effort. Tiers order the report
# rather than rating a defect's blast radius, so they map onto the shared
# severity scale here — the scale only feeds judge context, never a score.
AUDIT_TIER_SEV = {"T0": "CRITICAL", "T1": "HIGH", "T2": "MEDIUM",
                  "T3": "MEDIUM", "T4": "LOW", "T5": "LOW"}
TIER_CELL_RE = re.compile(r"^\[?(T[0-5])\]?$")
SEP_CELL_RE = re.compile(r"^:?-{2,}:?$")

def split_row(line):
    cells = line.strip().strip("|").split("|")
    return [c.strip().strip("`") for c in cells]

def parse_audit_findings(text, facet):
    blocks = []
    for line in text.splitlines():
        s = line.strip()
        if not s.startswith("|"):
            continue
        cells = split_row(s)
        if len(cells) < 5:
            continue
        if all(SEP_CELL_RE.match(c) for c in cells if c):
            continue                      # |---|---| separator
        # The tier cell anchors the row. The contract puts an id before it, but a
        # reviewer that drops the id column still emits gradeable findings —
        # locating the tier instead of counting columns keeps those.
        ti = next((i for i in (1, 0) if TIER_CELL_RE.match(cells[i])), None)
        if ti is None:
            continue                      # header row, or a table that is not this one
        tier = TIER_CELL_RE.match(cells[ti]).group(1)
        rest = cells[ti + 1:]
        if len(rest) < 3:
            continue
        f, a, b = parse_file_field(rest[0])
        evidence, fix = rest[2], (rest[3] if len(rest) > 3 else "")
        blocks.append({
            "severity": AUDIT_TIER_SEV.get(tier, "LOW"), "tier": tier,
            "title": rest[1], "facet": facet,
            "file": f or None, "line_start": a, "line_end": b,
            "confidence": None, "decision_type": None, "origin": None,
            "has_evidence": bool(evidence),
            "body": ["**Evidence:** " + evidence, "**Fix:** " + fix],
        })
    return blocks

COUPLING_RE = re.compile(r"^###\s+\[?COUPLED\]?[:\s]+(.+)$", re.I)
SHARED_RE = re.compile(r"\*\*Shared:?\*\*:?\s*`?([^\s`]+?)`?\s*$")
# Every coupling costs the same thing — two delegates landing in one file — so
# there is no severity ladder to borrow here. Fixing the weight at HIGH keeps
# recall_weighted equal to recall_must for this module rather than inventing a
# gradient the ground truth cannot justify.
COUPLING_SEV = "HIGH"

def parse_partition_couplings(text, facet):
    blocks = []
    cur = None
    for line in text.splitlines():
        m = COUPLING_RE.match(line.strip())
        if m:
            cur = {"severity": COUPLING_SEV, "verdict": "COUPLED",
                   "title": m.group(1).strip(), "facet": facet,
                   "file": None, "line_start": None, "line_end": None,
                   "confidence": None, "decision_type": None, "origin": None,
                   "has_evidence": False, "body": []}
            blocks.append(cur)
            continue
        if line.startswith("## ") and cur is not None:
            cur = None  # left the coupling region (e.g. Partition Summary)
        if cur is None:
            continue
        cur["body"].append(line)
        sm = SHARED_RE.search(line)
        if sm and cur["file"] is None:
            f, a, b = parse_file_field(sm.group(1).strip())
            cur["file"], cur["line_start"], cur["line_end"] = f, a, b
        conf = CONF_RE.search(line)
        if conf: cur["confidence"] = int(conf.group(1))
        if "**Evidence" in line:
            cur["has_evidence"] = True
    return blocks

SECTION_RE = re.compile(r"^###\s+(.+?)\s*$")
BULLET_RE = re.compile(r"^[-*]\s+(.*)$")
BACKTICK_RE = re.compile(r"`([^`\s]+)`")
PATH_TAIL_RE = re.compile(r"\.[A-Za-z0-9]{1,5}(:\d+(-\d+)?)?$")
# A recon item carries no failure mode, so there is no severity ladder to borrow.
# Fixing it at HIGH keeps recall_weighted driven by the RUBRIC's own severities
# (cmd_metrics weights ground truth, never findings) instead of by a gradient the
# reports cannot justify.
RECON_SEV = "HIGH"
# The Summary section is prose except for this one token, which downstream
# consumers key on (`codebase-explorer-agent.md` §Output Schema) — so it is
# scored as an item and the rest of the summary is not.
SUMMARY_SCORED_RE = re.compile(r"^(change_scope|Risk flags)\s*:", re.I)


def parse_recon_items(text, facet):
    """One finding per bullet in a Phase 1 recon report.

    Unlike the other parsers this reads the agents' OWN output schemas
    (`knowledge-retrieval-agent.md` / `codebase-explorer-agent.md` §Output
    Schema) rather than a block shape the stand imposes — the section headings
    and `- ` bullets those files already prescribe. Measuring the shipped
    contract is the point: a variant that changes the report's shape should
    show up as a parse difference, not be normalized away.

    The section heading rides in the title so the judge can tell a file cited as
    likely-touched from the same file cited as an exemplar — different claims
    about the same path, and the rubric scores them separately.
    """
    blocks = []
    section = None
    cur = None
    for raw_line in text.splitlines():
        line = raw_line.rstrip()
        if line.startswith("## "):
            section, cur = None, None      # report title / left the section region
            continue
        m = SECTION_RE.match(line)
        if m:
            section, cur = m.group(1).strip(), None
            continue
        if section is None:
            continue
        bm = BULLET_RE.match(line)
        if bm and not raw_line.startswith((" ", "\t")):
            body = bm.group(1).strip()
            # The orchestrator-summary section is prose the rubric cannot score,
            # with two named exceptions consumers actually key on.
            if section.lower().startswith("summary") and not SUMMARY_SCORED_RE.match(body):
                cur = None
                continue
            cur = {"severity": RECON_SEV, "verdict": "ITEM",
                   "title": "%s: %s" % (section, body[:200]), "facet": facet,
                   "section": section,
                   "file": None, "line_start": None, "line_end": None,
                   "confidence": None, "decision_type": None, "origin": None,
                   "has_evidence": False, "body": [body]}
            for tok in BACKTICK_RE.findall(body):
                # A bare symbol name is not a path: the reuse inventory cites the
                # helper first and its location second, and the location is what
                # the rubric matches on. A dot alone is too weak a signal —
                # `req.tenantId` and `cli.available_formats` are dotted symbols,
                # so an unrooted token also has to end in something extension-
                # shaped (`.ts`, `.json`, `.jsonl`, `.mdc`) to count.
                if "/" in tok or PATH_TAIL_RE.search(tok):
                    f, a, b = parse_file_field(tok)
                    cur["file"], cur["line_start"], cur["line_end"] = f, a, b
                    break
            blocks.append(cur)
            continue
        if cur is not None and line.strip():
            cur["body"].append(line.strip())   # sub-bullet / continuation
    return blocks

# Every non-default output shape, by its target.json `parser` value.
PARSERS = {
    "spec-claims": parse_spec_claims,
    "audit-findings": parse_audit_findings,
    "partition-couplings": parse_partition_couplings,
    "recon-items": parse_recon_items,
}

def cmd_parse(paths, parser="review-findings"):
    findings = []
    for path in paths:
        facet = re.sub(r"^raw-|\.json$", "", os.path.basename(path))
        text, usage, is_err = load_result_text(path)
        if is_err:
            continue
        if parser in PARSERS:
            blocks = PARSERS[parser](text, facet)
            for b in blocks:
                b["body"] = "\n".join(b["body"])[:2000]
            findings.extend(blocks)
            continue
        blocks = []
        cur = None
        for line in text.splitlines():
            m = FINDING_RE.match(line.strip())
            if m:
                cur = {"severity": m.group(1), "title": m.group(2).strip(), "facet": facet,
                       "file": None, "line_start": None, "line_end": None,
                       "confidence": None, "decision_type": None, "origin": None,
                       "has_evidence": False, "body": []}
                blocks.append(cur)
                continue
            if line.startswith("## ") and cur is not None:
                cur = None  # left the findings region (e.g. Dimension Summary)
            if cur is None:
                continue
            cur["body"].append(line)
            fm = FILE_RE.search(line)
            if fm and cur["file"] is None:
                f, a, b = parse_file_field(fm.group(1).strip())
                cur["file"], cur["line_start"], cur["line_end"] = f, a, b
            cm = CONF_RE.search(line)
            if cm: cur["confidence"] = int(cm.group(1))
            dm = DT_RE.search(line)
            if dm: cur["decision_type"] = dm.group(1)
            om = ORIGIN_RE.search(line)
            if om: cur["origin"] = om.group(1)
            if "**Evidence" in line or "## Evidence Block" in line:
                cur["has_evidence"] = True
        for b in blocks:
            b["body"] = "\n".join(b["body"])[:2000]
        findings.extend(blocks)
    for i, f in enumerate(findings):
        f["id"] = "F%d" % (i + 1)
    json.dump(findings, sys.stdout, indent=1)

# Judge wording, per module. The defaults reproduce the review/spec-check/
# partition prompt byte-for-byte, so a module that declares no `judge_framing`
# grades exactly as it did before this knob existed and its standing baselines
# stay comparable. A module whose artifact is not a defect list overrides the
# nouns: telling a judge to grade "defects" when the findings are files and
# learnings pushes every correct item into the noise bucket, which would not
# just add error — it would invert the axis.
JUDGE_FRAMING = {
    "intro": "You are grading a code review against a known ground-truth defect list. "
             "Return STRICT JSON only — no prose, no markdown fences.",
    "gt_heading": "Ground-truth defects",
    "negative_note": "(none — this is a NEGATIVE task: the change is believed clean, "
                     "so every finding below goes to residue)",
    "findings_heading": "Review findings to grade",
    "gt_noun": "ground-truth defect",
    "match_rule": "SAME defect — same root cause, not merely the same file or nearby lines. A finding\n"
                  "   that flags the right line for a different reason is NOT a match.",
    "plausible_real": "a concrete, plausibly correct defect claim with evidence, just\n"
                      "     not in the ground-truth list",
    "noise": "speculative, wrong, unverifiable, or describes correct code as broken",
    "nitpick": "real but trivial style/taste observation with no failure mode",
}

JUDGE_INSTRUCTIONS = """
## Instructions

1. For EACH %(gt_noun)s, decide which findings (if any) genuinely describe the
   %(match_rule)s Give a one-line
   "reason" quoting the finding phrase that establishes the match.
2. If you cannot tell whether a finding matches, do NOT match it — put it in residue
   with bucket "noise" and reason "unclear match". Never guess.
3. For EACH finding matched to no %(gt_noun)s, classify it:
   - "plausible-real": %(plausible_real)s
   - "noise": %(noise)s
   - "nitpick": %(nitpick)s
4. Judge only from what is shown. Be strict about matches. Concise findings grade the
   same as verbose ones — never reward length.

Return exactly this JSON shape:
{"matches": [{"gt_id": "...", "finding_ids": ["F1"], "reason": "<one line>"}, ...],
 "residue": [{"finding_id": "...", "bucket": "plausible-real|noise|nitpick", "reason": "<one line>"}, ...]}
Include every ground-truth id in "matches" (empty finding_ids if missed) and every
unmatched finding in "residue"."""


# Some ground truth is about what a report must NOT claim — a decoy learning it
# should have filtered, a rule whose glob does not match the change. Those items
# carry `polarity: "absence"`, and the ONLY faithful way to score them is to
# invert the found-test: satisfied when no finding matched. Without this the
# judge has to invent a convention per run, and it does — an A-vs-A on the recon
# module had one arm attach the "correctly excluded" finding and the other leave
# the list empty, from identical instructions, turning a stable behavior into a
# recall delta that was pure scoring artifact.
ABSENCE_RULE = """
NOTE — some ground-truth items carry "polarity": "absence". Those describe
something the report was required NOT to assert. Grade them by this rule and no
other: list a finding under such an item ONLY if that finding actually asserts
the thing as true or applicable. If no finding asserts it — including when the
report never mentions it at all, or mentions it only to rule it out — return the
item with an EMPTY finding_ids list. An empty list means the report behaved
correctly on an absence item, not that it missed something."""


def load_judge_framing(target_path=None):
    framing = dict(JUDGE_FRAMING)
    if target_path and os.path.exists(target_path):
        try:
            override = (json.load(open(target_path)) or {}).get("judge_framing") or {}
        except Exception:
            override = {}
        for k, v in override.items():
            if k in framing and isinstance(v, str):
                framing[k] = v
    return framing


def cmd_judgeprompt(rubric_path, findings_path, target_path=None):
    fr = load_judge_framing(target_path)
    rubric = load_rubric(rubric_path)
    gt = rubric["items"]
    findings = json.load(open(findings_path))
    # Deterministic shuffle (keyed on content) so ordering cannot systematically
    # favor one facet's findings across the whole benchmark.
    rnd = random.Random(len(findings) * 31 + len(gt))
    findings = findings[:]
    rnd.shuffle(findings)
    lines = []
    lines.append(fr["intro"])
    lines.append("\n## %s\n" % fr["gt_heading"])
    if not gt:
        lines.append(fr["negative_note"])
    for g in gt:
        row = {"gt_id": g["id"], "file": g.get("file"), "lines": g.get("lines"),
               "class": g.get("class"), "severity": g.get("severity"),
               "description": g.get("description")}
        if g.get("polarity") == "absence":
            row["polarity"] = "absence"
        lines.append(json.dumps(row))
    if any(g.get("polarity") == "absence" for g in gt):
        lines.append(ABSENCE_RULE)
    lines.append("\n## %s\n" % fr["findings_heading"])
    for f in findings:
        lines.append(json.dumps({
            "finding_id": f["id"], "severity": f.get("severity"), "title": f.get("title"),
            "file": f.get("file"), "lines": [f.get("line_start"), f.get("line_end")],
            "excerpt": (f.get("body") or "")[:600]}))
    lines.append(JUDGE_INSTRUCTIONS % fr)
    sys.stdout.write("\n".join(lines))

def cmd_extract(judge_raw_path):
    text, _, is_err = load_result_text(judge_raw_path)
    if is_err:
        sys.exit(65)
    m = re.search(r"\{.*\}", text, re.DOTALL)
    if not m:
        sys.exit(65)
    try:
        obj = json.loads(m.group(0))
    except Exception:
        sys.exit(65)
    json.dump(obj, sys.stdout)

def contested_must(must, by_gt, residue, findings):
    """Missed must-finds whose own lines a discarded finding already cites.

    A run that looked exactly where the rubric points and drew the opposite
    conclusion is a different animal from a run that never looked. The first is
    usually a defective fixture — the ground truth asserts something the tree
    does not support — and it costs twice, once in recall and again in noise.
    Scoring is untouched: this only tells the transcript read which trial to
    open first.
    """
    by_id = {f.get("id"): f for f in findings}
    out = []
    for g in must:
        # Absence items have no "looked and concluded otherwise" failure mode —
        # they fail by an ASSERTION being present, which is not a missed find.
        if g.get("polarity") == "absence" or by_gt.get(g["id"]):
            continue
        lines = g.get("lines") or []
        lo = lines[0] if lines else None
        hi = lines[1] if len(lines) > 1 else lo
        hits = []
        for fid, bucket in residue.items():
            if bucket not in ("noise", "nitpick"):
                continue
            f = by_id.get(fid)
            if not f or not f.get("file") or f["file"] != g.get("file"):
                continue
            fs, fe = f.get("line_start"), f.get("line_end")
            if lo is None or fs is None or (fs <= hi and (fe or fs) >= lo):
                hits.append(fid)
        if hits:
            out.append({"gt_id": g["id"], "finding_ids": sorted(hits)})
    return out

def cmd_vote(paths):
    """Consensus over N independent judge verdicts on the SAME findings.

    Match verdicts reproduce; residue bucketing does not — two passes over one
    finding set re-bucket unmatched findings by ~2.4 per task, which is the same
    order as the between-arm delta an A-vs-A is trying to resolve. A single
    judge call therefore reports a noise figure that a rerun would not confirm.
    Modal bucket over an odd panel collapses that: a finding both passes call
    noise stays noise, and one they split lands wherever the third vote falls
    (PoLL, arXiv 2404.18796). Ties break toward the more conservative bucket —
    plausible-real over nitpick over noise — so a contested finding is never
    counted against the reviewer on a coin flip.
    """
    from collections import Counter
    verdicts = [json.load(open(p)) for p in paths]
    gt_ids, finding_ids = [], []
    for v in verdicts:
        for m in v.get("matches", []):
            if m.get("gt_id") not in gt_ids:
                gt_ids.append(m["gt_id"])
        for r in v.get("residue", []):
            if r.get("finding_id") not in finding_ids:
                finding_ids.append(r["finding_id"])
    need = len(verdicts) / 2.0
    matches = []
    for g in gt_ids:
        hits = Counter()
        for v in verdicts:
            for m in v.get("matches", []):
                if m.get("gt_id") == g:
                    for fid in (m.get("finding_ids") or []):
                        hits[fid] += 1
        ids = sorted(f for f, c in hits.items() if c > need)
        matches.append({"gt_id": g, "finding_ids": ids,
                        "reason": "panel of %d, matched by >%d" % (len(verdicts), need)})
    matched = {f for m in matches for f in m["finding_ids"]}
    order = {"plausible-real": 0, "nitpick": 1, "noise": 2}
    residue = []
    for fid in finding_ids:
        if fid in matched:
            continue          # the panel matched it; it is not residue
        votes = Counter()
        for v in verdicts:
            for r in v.get("residue", []):
                if r.get("finding_id") == fid and r.get("bucket"):
                    votes[r["bucket"]] += 1
        if not votes:
            continue
        top = max(votes.values())
        bucket = sorted((b for b, c in votes.items() if c == top), key=lambda b: order[b])[0]
        residue.append({"finding_id": fid, "bucket": bucket,
                        "reason": "panel %s" % dict(votes)})
    json.dump({"matches": matches, "residue": residue}, sys.stdout)


def cmd_metrics(task_path, rubric_path, findings_path, match_path, raw_dir):
    task = json.load(open(task_path))
    rubric = load_rubric(rubric_path)
    gt = rubric["items"]
    findings = json.load(open(findings_path))
    match = json.load(open(match_path))
    by_gt = {m["gt_id"]: m.get("finding_ids") or [] for m in match.get("matches", [])}
    residue = {r["finding_id"]: r.get("bucket") for r in match.get("residue", [])}
    def satisfied(g):
        # An absence item inverts the test: it is satisfied when NOTHING matched
        # it, because the claim it encodes is that the report must not assert it.
        matched = bool(by_gt.get(g["id"]))
        return (not matched) if g.get("polarity") == "absence" else matched

    must = [g for g in gt if g.get("must_find", True)]
    found_must = [g for g in must if satisfied(g)]
    all_found = [g for g in gt if satisfied(g)]
    w_total = sum(SEV_W.get(g.get("severity", "MEDIUM"), 2) for g in gt) or 1
    w_found = sum(SEV_W.get(g.get("severity", "MEDIUM"), 2) for g in all_found)
    n_noise = sum(1 for b in residue.values() if b == "noise")
    n_nitpick = sum(1 for b in residue.values() if b == "nitpick")
    n_plausible = sum(1 for b in residue.values() if b == "plausible-real")
    matched_ids = set(fid for ids in by_gt.values() for fid in ids)
    contested = contested_must(must, by_gt, residue, findings)
    tok_in = tok_out = 0
    wall = 0
    for p in glob.glob(os.path.join(raw_dir, "raw-*.json")):
        try:
            raw = json.load(open(p))
        except Exception:
            continue
        u = raw.get("usage") or {}
        tok_in += (u.get("inputTokens") or 0) + (u.get("cacheReadTokens") or 0)
        tok_out += u.get("outputTokens") or 0
        wall = max(wall, raw.get("duration_ms") or 0)
    out = {
        "task": task.get("id") or os.path.basename(os.path.dirname(task_path)),
        "rubric_version": rubric["version"],
        "gt_absence": sum(1 for g in gt if g.get("polarity") == "absence"),
        "negative": bool(rubric["negative"]),
        "gt_total": len(gt), "gt_must": len(must),
        "recall_must": round(len(found_must) / len(must), 4) if must else None,
        "recall_all": round(len(all_found) / len(gt), 4) if gt else None,
        "recall_weighted": round(w_found / w_total, 4) if gt else None,
        "findings_total": len(findings),
        "matched_findings": len(matched_ids),
        "plausible_real": n_plausible,
        "noise": n_noise + n_nitpick,   # combined noise axis (back-compat with cursor-review)
        "noise_strict": n_noise,
        "nitpick": n_nitpick,
        "precision_proxy": round((len(matched_ids) + n_plausible) / len(findings), 4) if findings else None,
        "tokens_in": tok_in, "tokens_out": tok_out, "wall_ms": wall,
        "missed_must": [g["id"] for g in must if not satisfied(g)],
        "contested_must": contested,
    }
    json.dump(out, sys.stdout, indent=1)

if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "parse":
        args = sys.argv[2:]
        parser = "review-findings"
        if args and args[0] == "--parser":
            parser = args[1]; args = args[2:]
        cmd_parse(args, parser)
    elif cmd == "judgeprompt": cmd_judgeprompt(*sys.argv[2:5])
    elif cmd == "extract": cmd_extract(sys.argv[2])
    elif cmd == "vote": cmd_vote(sys.argv[2:])
    elif cmd == "metrics": cmd_metrics(*sys.argv[2:7])
    else:
        sys.stderr.write(__doc__)
        sys.exit(64)
