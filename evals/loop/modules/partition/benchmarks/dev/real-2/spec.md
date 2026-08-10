# Desktop app batch 7

Four approved items for the desktop app, scoped separately.

## Todos

### todo-1 — Export run transcript to a file

The user should be able to export a run's transcript. The renderer needs to ask
the privileged side to open a save dialog and write the file, then get back the
path it wrote.

### todo-2 — Reveal the workspace folder

Add a "Show in Finder" action on a project. The renderer needs to ask the
privileged side to reveal the project's folder in the OS file manager.

### todo-3 — Transcript virtualization

Long transcripts drop frames while scrolling. Virtualize the transcript list so
only visible turns render. Renderer-side only; no new data is required.

### todo-4 — Daemon log rotation

The daemon's log file grows without bound. Rotate it at 50 MB, keeping three
generations.
