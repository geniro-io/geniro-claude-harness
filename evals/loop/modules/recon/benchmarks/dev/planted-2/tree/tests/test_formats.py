import io

from reporting.formats import csv_format, table_format


def test_csv_writes_header():
    buf = io.StringIO()
    csv_format.write(("a", "b"), [("1", "2")], buf)
    assert buf.getvalue().splitlines()[0] == "a,b"


def test_table_pads_columns():
    buf = io.StringIO()
    table_format.write(("a", "bbb"), [("1", "2")], buf)
    assert buf.getvalue().splitlines()[0] == "a | bbb"
