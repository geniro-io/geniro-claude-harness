import importlib
import pkgutil
import sys

import click

from reporting import formats
from reporting.source import fetch_rows


def available_formats() -> list[str]:
    return sorted(m.name for m in pkgutil.iter_modules(formats.__path__))


@click.command()
@click.option("--format", "fmt", default="table_format", type=click.Choice(available_formats()))
def main(fmt: str) -> None:
    module = importlib.import_module(f"reporting.formats.{fmt}")
    headers, rows = fetch_rows()
    module.write(headers, rows, sys.stdout)
