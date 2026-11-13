# A wizard generator for human-only steps

A skill that generates an interactive bash script walking the user through steps only a human can do (credentials, third-party dashboards, cutovers).

## Why this is out of scope

No observed failure in a Geniro session shows a run stalling on a human-only step that such a script would have fixed. A change needs an observed failure or an explicit user decision to clear the bar, and this has neither.

## Prior requests

- 2026-11-13: raised while comparing Pocock's `wizard` with Geniro's skills; no observed failure.
