#!/usr/bin/env python3
"""evals/loop scoring library (module-agnostic core).

Subcommands:
  parse   <raw-*.json ...>                 -> findings JSON on stdout
  judgeprompt <rubric.json> <findings.json>  -> judge prompt on stdout
  extract <judge-raw.json>                 -> the judge's JSON verdict on stdout
  metrics <task.json> <rubric.json> <findings.json> <match.json> <raw-dir>
                                           -> per-trial metrics JSON on stdout

A rubric is {"version": int, "negative": bool, "items": [...]}; a bare legacy
array is accepted and treated as version 0. Items use the ground-truth schema
(id/file/lines/class/severity/must_find/description).

Two parsers ship: `review-findings` (the /geniro:review §Output Format shape)
and `spec-claims` (the spec-challenge per-claim verdict shape). A module names
the one it needs in its target.json `parser` field; a new output shape adds a
function here and a PARSERS entry.

`spec-claims` emits one finding per claim the run judged WRONG — refuted or
clarified — and none for a confirmed claim. That keeps the rubric on the same
footing as every other module's: its items are the claims that are genuinely
wrong, so recall_must reads "did the pass catch the bad claims" and noise reads
"did it flag good ones", with cmd_metrics unchanged.
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

def cmd_parse(paths, parser="review-findings"):
    findings = []
    for path in paths:
        facet = re.sub(r"^raw-|\.json$", "", os.path.basename(path))
        text, usage, is_err = load_result_text(path)
        if is_err:
            continue
        if parser == "spec-claims":
            blocks = parse_spec_claims(text, facet)
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

def cmd_judgeprompt(rubric_path, findings_path):
    rubric = load_rubric(rubric_path)
    gt = rubric["items"]
    findings = json.load(open(findings_path))
    # Deterministic shuffle (keyed on content) so ordering cannot systematically
    # favor one facet's findings across the whole benchmark.
    rnd = random.Random(len(findings) * 31 + len(gt))
    findings = findings[:]
    rnd.shuffle(findings)
    lines = []
    lines.append("You are grading a code review against a known ground-truth defect list. "
                 "Return STRICT JSON only — no prose, no markdown fences.")
    lines.append("\n## Ground-truth defects\n")
    if not gt:
        lines.append("(none — this is a NEGATIVE task: the change is believed clean, "
                     "so every finding below goes to residue)")
    for g in gt:
        lines.append(json.dumps({
            "gt_id": g["id"], "file": g.get("file"), "lines": g.get("lines"),
            "class": g.get("class"), "severity": g.get("severity"),
            "description": g.get("description")}))
    lines.append("\n## Review findings to grade\n")
    for f in findings:
        lines.append(json.dumps({
            "finding_id": f["id"], "severity": f.get("severity"), "title": f.get("title"),
            "file": f.get("file"), "lines": [f.get("line_start"), f.get("line_end")],
            "excerpt": (f.get("body") or "")[:600]}))
    lines.append("""
## Instructions

1. For EACH ground-truth defect, decide which findings (if any) genuinely describe the
   SAME defect — same root cause, not merely the same file or nearby lines. A finding
   that flags the right line for a different reason is NOT a match. Give a one-line
   "reason" quoting the finding phrase that establishes the match.
2. If you cannot tell whether a finding matches, do NOT match it — put it in residue
   with bucket "noise" and reason "unclear match". Never guess.
3. For EACH finding matched to no ground-truth defect, classify it:
   - "plausible-real": a concrete, plausibly correct defect claim with evidence, just
     not in the ground-truth list
   - "noise": speculative, wrong, unverifiable, or describes correct code as broken
   - "nitpick": real but trivial style/taste observation with no failure mode
4. Judge only from what is shown. Be strict about matches. Concise findings grade the
   same as verbose ones — never reward length.

Return exactly this JSON shape:
{"matches": [{"gt_id": "...", "finding_ids": ["F1"], "reason": "<one line>"}, ...],
 "residue": [{"finding_id": "...", "bucket": "plausible-real|noise|nitpick", "reason": "<one line>"}, ...]}
Include every ground-truth id in "matches" (empty finding_ids if missed) and every
unmatched finding in "residue".""")
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
        if by_gt.get(g["id"]):
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

def cmd_metrics(task_path, rubric_path, findings_path, match_path, raw_dir):
    task = json.load(open(task_path))
    rubric = load_rubric(rubric_path)
    gt = rubric["items"]
    findings = json.load(open(findings_path))
    match = json.load(open(match_path))
    by_gt = {m["gt_id"]: m.get("finding_ids") or [] for m in match.get("matches", [])}
    residue = {r["finding_id"]: r.get("bucket") for r in match.get("residue", [])}
    must = [g for g in gt if g.get("must_find", True)]
    found_must = [g for g in must if by_gt.get(g["id"])]
    all_found = [g for g in gt if by_gt.get(g["id"])]
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
        "missed_must": [g["id"] for g in must if not by_gt.get(g["id"])],
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
    elif cmd == "judgeprompt": cmd_judgeprompt(sys.argv[2], sys.argv[3])
    elif cmd == "extract": cmd_extract(sys.argv[2])
    elif cmd == "metrics": cmd_metrics(*sys.argv[2:7])
    else:
        sys.stderr.write(__doc__)
        sys.exit(64)
