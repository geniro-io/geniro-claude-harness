---
applyTo: "services/**/*.py"
---

Every service module exposes a single `handle` entry point and keeps its
transport concerns out of the domain layer.
