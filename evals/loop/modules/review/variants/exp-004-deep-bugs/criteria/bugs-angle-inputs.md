# Angle for this pass: hostile inputs and failure paths

Apply the criteria above through this lens only — a sibling pass covers the
general case. Assume every input is hostile and every dependency fails:
rejected promises and throwing callees, non-2xx and network failures,
empty/null/oversized payloads, concurrent double-invocation. For each changed
entry point, trace the failure path to its user-visible end state — a
swallowed rejection, or state left stuck (spinner, lock, disabled action), is
a finding.
