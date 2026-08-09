#!/usr/bin/env python3
"""Judge-calibration helper.

  kappa.py sample <run-dir> [-n N]   -> pending-<stamp>.jsonl next to this file
  kappa.py score  <labeled.jsonl>    -> kappa / agreement / TPR / TNR on stdout

Row shape (one JSON object per line):
  {"task": "...", "trial": "trial-1", "kind": "match|residue",
   "gt_id": "...", "finding_id": "...",
   "judge": "matched|missed|plausible-real|noise|nitpick",
   "human": null}          # <- the human fills this in, same vocabulary

score treats kind=match rows as the binary judge (matched vs missed) for
TPR/TNR, and computes Cohen's kappa over all rows with a non-null human label.
"""
import json, sys, os, glob, random, datetime

def rows_from_run(run_dir):
    rows = []
    for mpath in glob.glob(os.path.join(run_dir, "results", "*", "trial-*", "match.json")):
        trdir = os.path.dirname(mpath)
        task = os.path.basename(os.path.dirname(trdir))
        trial = os.path.basename(trdir)
        try:
            match = json.load(open(mpath))
        except Exception:
            continue
        for m in match.get("matches", []):
            rows.append({"task": task, "trial": trial, "kind": "match",
                         "gt_id": m.get("gt_id"), "finding_id": ",".join(m.get("finding_ids") or []),
                         "judge": "matched" if m.get("finding_ids") else "missed",
                         "reason": m.get("reason"), "human": None})
        for r in match.get("residue", []):
            rows.append({"task": task, "trial": trial, "kind": "residue",
                         "gt_id": None, "finding_id": r.get("finding_id"),
                         "judge": r.get("bucket"), "reason": r.get("reason"), "human": None})
    return rows

def cmd_sample(run_dir, n):
    rows = rows_from_run(run_dir)
    if not rows:
        sys.exit("no match.json rows under " + run_dir)
    random.Random(1234).shuffle(rows)
    rows = rows[:n]
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "pending-%s.jsonl" % stamp)
    with open(out, "w") as f:
        for r in rows:
            f.write(json.dumps(r) + "\n")
    print("wrote %d rows -> %s\nlabel each row's \"human\" field, then: kappa.py score %s" % (len(rows), out, out))

def cmd_score(path):
    rows = [json.loads(l) for l in open(path) if l.strip()]
    labeled = [r for r in rows if r.get("human")]
    if not labeled:
        sys.exit("no labeled rows (fill the human field)")
    agree = sum(1 for r in labeled if r["judge"] == r["human"])
    po = agree / len(labeled)
    # Cohen's kappa over the full label vocabulary
    cats = sorted(set([r["judge"] for r in labeled] + [r["human"] for r in labeled]))
    pj = {c: sum(1 for r in labeled if r["judge"] == c) / len(labeled) for c in cats}
    ph = {c: sum(1 for r in labeled if r["human"] == c) / len(labeled) for c in cats}
    pe = sum(pj[c] * ph[c] for c in cats)
    kappa = (po - pe) / (1 - pe) if pe < 1 else 1.0
    # Binary TPR/TNR on match rows: positive = "matched" per the HUMAN label
    m = [r for r in labeled if r["kind"] == "match"]
    tp = sum(1 for r in m if r["human"] == "matched" and r["judge"] == "matched")
    fn = sum(1 for r in m if r["human"] == "matched" and r["judge"] != "matched")
    tn = sum(1 for r in m if r["human"] == "missed" and r["judge"] == "missed")
    fp = sum(1 for r in m if r["human"] == "missed" and r["judge"] != "missed")
    out = {"labeled": len(labeled), "agreement": round(po, 3), "kappa": round(kappa, 3),
           "match_rows": len(m),
           "tpr": round(tp / (tp + fn), 3) if (tp + fn) else None,
           "tnr": round(tn / (tn + fp), 3) if (tn + fp) else None,
           "disagreements": [{"task": r["task"], "kind": r["kind"],
                              "gt_id": r.get("gt_id"), "finding_id": r.get("finding_id"),
                              "judge": r["judge"], "human": r["human"]}
                             for r in labeled if r["judge"] != r["human"]]}
    json.dump(out, sys.stdout, indent=1)
    print()

if __name__ == "__main__":
    if len(sys.argv) >= 3 and sys.argv[1] == "sample":
        n = int(sys.argv[sys.argv.index("-n") + 1]) if "-n" in sys.argv else 20
        cmd_sample(sys.argv[2], n)
    elif len(sys.argv) >= 3 and sys.argv[1] == "score":
        cmd_score(sys.argv[2])
    else:
        sys.stderr.write(__doc__)
        sys.exit(64)
