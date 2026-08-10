import csv
from typing import Iterable, Sequence, TextIO


def write(headers: Sequence[str], rows: Iterable[Sequence[str]], stream: TextIO) -> None:
    writer = csv.writer(stream)
    writer.writerow(headers)
    for row in rows:
        writer.writerow(row)
