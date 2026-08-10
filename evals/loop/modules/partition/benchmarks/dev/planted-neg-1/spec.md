# Small fixes batch

Three unrelated defects, each reported by a different team.

## Todos

### todo-1 — Search pagination is off by one

`pageSlice` takes a 1-based page number but multiplies it directly by the page
size, so page 1 skips the first 25 results and page 0 is silently valid. Fix the
arithmetic so page 1 returns the first 25.

### todo-2 — CSV export must use semicolons

Finance opens exports in a locale where comma is the decimal separator, so the
columns split wrongly. Change the export delimiter to a semicolon.

### todo-3 — Dark theme foreground fails contrast

The dark palette's foreground against its background is below the 4.5:1 contrast
minimum. Lighten the foreground until it passes.
