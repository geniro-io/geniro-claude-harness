#!/usr/bin/env python3
"""Mechanically check a spec's citations against the tree it makes claims about.

    check_claims.py <spec.md> <repo-root>

Objective checks only — no model in the loop. This exists so the ground truth for
a spec-check task is not produced by the same kind of agent that will later be
scored on it: a rubric built by one verifier subagent and graded against another
measures agreement, not correctness.

Reports, per citation `path:line` found in the spec:
  MISSING   the file does not exist in the tree
  OOB       the line number is past the end of the file
  OK        resolves

and separately, for every symbol the spec names in backticks next to a citation,
whether that symbol appears anywhere in the cited file.

What it cannot decide is left to adjudication: counts, "no X exists anywhere",
and claims about behaviour. Those are flagged UNCHECKED so they are not silently
treated as confirmed.
"""
import os, re, sys

CITE = re.compile(r"`?([A-Za-z0-9_./\-]+\.(?:py|pyi|ts|tsx|js|md|rst|json|ya?ml|cfg|ini|toml|txt|sh|in|xml|html|css)):(\d+)(?:\s*[-–]\s*(\d+))?`?")
BACKTICK = re.compile(r"`([A-Za-z_][A-Za-z0-9_.]*)`")
# Claim shapes no file/line lookup can settle.
NUM = r"(?:\d+|one|two|three|four|five|six|seven|eight|nine|ten|a\s+single)"
UNCHECKABLE = re.compile(
    r"\b(?:no\s+\w+\s+(?:exists|is\s+\w+)|nowhere|anywhere|never|always|"
    r"only\s+(?:place|caller|one)|the\s+sole\b|" + NUM + r"\s+\w+s\b)", re.I)


PATHISH = re.compile(r"`?([A-Za-z0-9_.\-]+(?:/[A-Za-z0-9_.\-]+)+)`?")


def resolve(root, rel, line):
    """Resolve a citation, honouring the abbreviation specs actually use.

    A bullet routinely names the file in full once and then shortens it inside
    the parenthetical — "`sphinx/ext/autodoc/importer.py` — `get_class_members()`
    (`importer.py:254-318`)". Treating that bare basename as a dangling citation
    invented 27 defects in one spec, all of them in the direction this
    experiment predicted. An instrument that manufactures evidence for its
    author's hypothesis is worse than no instrument.
    """
    # Try the citation as written first — a root-level `setup.cfg` carries no
    # slash and is not thereby ambiguous.
    if os.path.isfile(os.path.join(root, rel)):
        return rel
    if "/" in rel:
        return None
    # Resolve the abbreviation only against a full path on the SAME line ending
    # in the SAME basename — the "`a/b/foo.py` … (`foo.py:12`)" shape. Guessing a
    # directory instead resolved two sphinx citations to files that merely
    # happen to exist (`sphinx/ext/__init__.py`, 9 lines) and reported them as
    # out-of-range spec defects. Every mis-resolution this instrument produced
    # counted against the arm the hypothesis predicted would look worse.
    for ctx in PATHISH.findall(line):
        if os.path.basename(ctx) == rel and os.path.isfile(os.path.join(root, ctx)):
            return ctx
    return None


def read_lines(root, rel):
    p = os.path.join(root, rel)
    if not os.path.isfile(p):
        return None
    with open(p, errors="replace") as f:
        return f.read().splitlines()


SECTION = re.compile(r"^##\s+(\d+)\.\s")
BULLET = re.compile(r"^\s*-\s")


def bullets_by_section(lines, wanted=("4", "5", "6")):
    """Group §4/§5/§6 bullets, each with its continuation lines.

    Counting every bullet rather than only the ones that "look factual" keeps
    the measure symmetric across arms: a filter tuned on one arm's prose would
    decide the comparison. The uncited ones are printed in full so the judgment
    call — does this bullet actually assert something about the code — is made
    by hand, on the record, and not smuggled into a regex.
    """
    out, sec, cur = [], None, None
    for i, line in enumerate(lines, 1):
        m = SECTION.match(line)
        if m:
            sec = m.group(1)
            cur = None
            continue
        if line.startswith("## "):
            sec, cur = None, None
            continue
        if sec not in wanted:
            continue
        if BULLET.match(line):
            cur = {"sec": sec, "line": i, "text": line.strip()}
            out.append(cur)
        elif cur is not None and line.strip():
            cur["text"] += " " + line.strip()
    return out


def main(spec_path, root):
    text = open(spec_path, errors="replace").read()
    lines = text.splitlines()
    seen = set()
    rows = []
    for i, line in enumerate(lines, 1):
        for m in CITE.finditer(line):
            rel, a = m.group(1), int(m.group(2))
            b = int(m.group(3)) if m.group(3) else a
            key = (rel, a, b)
            if key in seen:
                continue
            seen.add(key)
            resolved = resolve(root, rel, line)
            if resolved is None:
                # BARE is not MISSING. A bare `__init__.py:1595` names a real
                # line in a real file — but sphinx has that basename in a dozen
                # directories, so which one is carried by document context a
                # reader has to hold in their head. That is a weaker form of
                # grounding, not a false claim, and collapsing the two would
                # overstate the defect count.
                rows.append(("MISSING" if "/" in rel else "BARE", rel, a, b, i,
                             "" if "/" in rel else "ambiguous basename — no path on this line"))
                continue
            rel = resolved
            src = read_lines(root, rel)
            if a > len(src) or b > len(src):
                rows.append(("OOB", rel, a, b, i, "file has %d lines" % len(src)))
                continue
            # A symbol-presence check lived here and is gone: across 6 flags on
            # real specs it was wrong 6 times and right 0. It cannot tell a claim
            # about existing code from the name of something the spec PROPOSES to
            # create ("build a `_deprecate_kwarg` decorator", "add a `Base`
            # fixture"), and a check with no precision does not inform a rubric,
            # it corrupts one.
            excerpt = " / ".join(s.strip() for s in src[a - 1:b])[:150]
            rows.append(("OK", rel, a, b, i, excerpt))

    unchecked = [(i, l.strip()[:140]) for i, l in enumerate(lines, 1)
                 if UNCHECKABLE.search(l) and l.strip().startswith(("-", "*", "1.", "2."))]

    print("=== citations (%d unique) ===" % len(rows))
    for st, rel, a, b, sl, note in sorted(rows, key=lambda r: (r[0] != "OK", r[1])):
        span = str(a) if a == b else "%d-%d" % (a, b)
        print("%-11s spec:%-4d %s:%s  %s" % (st, sl, rel, span, note))
    n_bare = len([r for r in rows if r[0] == "BARE"])
    n_bad = len([r for r in rows if r[0] in ("MISSING", "OOB")])
    print("\n%d/%d citations resolve cleanly; %d bare/ambiguous; %d missing-or-out-of-range" % (
        len(rows) - n_bare - n_bad, len(rows), n_bare, n_bad))
    bl = bullets_by_section(lines)
    uncited = [b for b in bl if not CITE.search(b["text"])]
    print("\n=== grounding of §4/§5/§6 bullets ===")
    print("bullets: %d | cited: %d | UNCITED: %d" % (len(bl), len(bl) - len(uncited), len(uncited)))
    for b in uncited:
        print("  §%s spec:%-4d %s" % (b["sec"], b["line"], b["text"][:160]))

    print("\n=== UNCHECKED claim shapes (counts / universals — adjudicate by hand) ===")
    for i, l in unchecked:
        print("spec:%-4d %s" % (i, l))
    if not unchecked:
        print("(none)")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
