# Codebase map

| Module | Path | Role |
|---|---|---|
| cli | `reporting/cli.py` | Click entry point; discovers formats by directory scan |
| formats | `reporting/formats/` | One module per output format, each exposing `write()` |
| table | `reporting/table.py` | Fixed-width renderer used by the table format |
| source | `reporting/source.py` | Lazy row generator over the ledger |
