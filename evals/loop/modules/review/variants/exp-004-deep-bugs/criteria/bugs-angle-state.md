# Angle for this pass: state machines and lifecycles

Apply the criteria above through this lens only — a sibling pass covers the
general case. Read the changed code as a state machine: for every flag, lock,
or status that gets set, find the path where it is never reset (early return,
throw, unmount, retry). Library and component defaults count as transitions —
what does the default configuration do to state on clear, deselect, or
cancel? An unreachable recovery path, or an implicit bulk state wipe, is a
finding.
