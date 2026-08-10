from typing import Iterable, Sequence, TextIO

from reporting.table import render


def write(headers: Sequence[str], rows: Iterable[Sequence[str]], stream: TextIO) -> None:
    stream.write(render(headers, rows))
    stream.write("\n")
