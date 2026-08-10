"""The report's only test: a byte-for-byte comparison against the golden file.

There is no assertion on individual columns anywhere in the suite. The golden
file IS the specification of the rendered output — if the report changes, the
golden file changes with it in the same commit, or the suite goes red.
"""

import json
from pathlib import Path

from report.render import render

HERE = Path(__file__).parent
FIXTURE = HERE / "fixtures" / "accounts.json"
GOLDEN = HERE / "golden" / "report.txt"


def test_report_matches_golden():
    accounts = json.loads(FIXTURE.read_text())
    assert render(accounts) == GOLDEN.read_text()
