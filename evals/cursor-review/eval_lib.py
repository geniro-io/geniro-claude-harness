#!/usr/bin/env python3
"""cursor-review scoring library.

Subcommands:
  parse   <raw-*.json ...>            -> findings JSON on stdout
  judgeprompt <ground_truth.json> <findings.json>  -> judge prompt on stdout
  extract <judge-raw.json>            -> the judge's JSON verdict on stdout
  metrics <task.json> <ground_truth.json> <findings.json> <match.json> <raw-dir>
                                      -> per-task metrics JSON on stdout
"""
import json, re, sys, glob, os, random

SEV_W = {"CRITICAL": 4, "HIGH": 3, "MEDIUM": 2, "LOW": 1}

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

def cmd_parse(paths):
    findings = []
    for path in paths:
        dim = re.sub(r"^raw-|\.json$", "", os.path.basename(path))
        text, usage, is_err = load_result_text(path)
        if is_err:
            continue
        blocks = []
        cur = None
        for line in text.splitlines():
            m = FINDING_RE.match(line.strip())
            if m:
                cur = {"severity": m.group(1), "title": m.group(2).strip(), "dim": dim,
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
        f["id"] = f"F{i+1}"
    json.dump(findings, sys.stdout, indent=1)

def cmd_judgeprompt(gt_path, findings_path):
    gt = json.load(open(gt_path))
    findings = json.load(open(findings_path))
    # Deterministic shuffle (keyed on content) so ordering cannot systematically
    # favor one dimension's findings across the whole benchmark.
    rnd = random.Random(len(findings) * 31 + len(gt))
    findings = findings[:]
    rnd.shuffle(findings)
    lines = []
    lines.append("You are grading a code review against a known ground-truth defect list. "
                 "Return STRICT JSON only — no prose, no markdown fences.")
    lines.append("\n## Ground-truth defects\n")
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
   that flags the right line for a different reason is NOT a match.
2. For EACH finding matched to no ground-truth defect, classify it:
   - "plausible-real": a concrete, plausibly correct defect claim with evidence, just
     not in the ground-truth list
   - "noise": speculative, wrong, unverifiable, or describes correct code as broken
   - "nitpick": real but trivial style/taste observation with no failure mode
3. Judge only from what is shown. Be strict about matches.

Return exactly this JSON shape:
{"matches": [{"gt_id": "...", "finding_ids": ["F1"]}, ...],
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

def cmd_metrics(task_path, gt_path, findings_path, match_path, raw_dir):
    task = json.load(open(task_path))
    gt = json.load(open(gt_path))
    findings = json.load(open(findings_path))
    match = json.load(open(match_path))
    by_gt = {m["gt_id"]: m.get("finding_ids") or [] for m in match.get("matches", [])}
    residue = {r["finding_id"]: r.get("bucket") for r in match.get("residue", [])}
    must = [g for g in gt if g.get("must_find", True)]
    found_must = [g for g in must if by_gt.get(g["id"])]
    all_found = [g for g in gt if by_gt.get(g["id"])]
    w_total = sum(SEV_W.get(g.get("severity", "MEDIUM"), 2) for g in gt) or 1
    w_found = sum(SEV_W.get(g.get("severity", "MEDIUM"), 2) for g in all_found)
    n_noise = sum(1 for b in residue.values() if b in ("noise", "nitpick"))
    n_plausible = sum(1 for b in residue.values() if b == "plausible-real")
    matched_ids = set(fid for ids in by_gt.values() for fid in ids)
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
        "gt_total": len(gt), "gt_must": len(must),
        "recall_must": round(len(found_must) / len(must), 4) if must else None,
        "recall_all": round(len(all_found) / len(gt), 4) if gt else None,
        "recall_weighted": round(w_found / w_total, 4),
        "findings_total": len(findings),
        "matched_findings": len(matched_ids),
        "plausible_real": n_plausible,
        "noise": n_noise,
        "precision_proxy": round((len(matched_ids) + n_plausible) / len(findings), 4) if findings else None,
        "tokens_in": tok_in, "tokens_out": tok_out, "wall_ms": wall,
        "missed_must": [g["id"] for g in must if not by_gt.get(g["id"])],
    }
    json.dump(out, sys.stdout, indent=1)

if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "parse": cmd_parse(sys.argv[2:])
    elif cmd == "judgeprompt": cmd_judgeprompt(sys.argv[2], sys.argv[3])
    elif cmd == "extract": cmd_extract(sys.argv[2])
    elif cmd == "metrics": cmd_metrics(*sys.argv[2:7])
    else:
        sys.stderr.write(__doc__)
        sys.exit(64)
