# Inventory API

Python 3.12. **Django 4.2** with DRF serializers on top.

## Commands

| What | Command |
|---|---|
| Install | `poetry install` |
| Test | `make check` |
| Lint | `make lint` |

## Layout

Settings live in `app/settings.py`. Environment overrides are read there and
nowhere else.

Models are in `app/models.py`; serializers in `app/serializers.py`.

## Conventions

- Every endpoint declares its response schema explicitly.
- Database access goes through the repository layer in `app/repo.py`.
