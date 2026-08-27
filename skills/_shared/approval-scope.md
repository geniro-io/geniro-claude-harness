# Approval scope — an approval reaches only what the user was shown

Canonical rule for how far a user's approval reaches. Referenced from `${CLAUDE_PLUGIN_ROOT}/skills/_shared/reporter-boundary.md`, `${CLAUDE_PLUGIN_ROOT}/skills/_shared/flags-reference.md`, `${CLAUDE_PLUGIN_ROOT}/skills/implement/SKILL.md`, `${CLAUDE_PLUGIN_ROOT}/skills/actions/SKILL.md`, and any skill that gates an outward or irreversible action. Define the rule here once; do not paste it into the calling skills.

## The rule

**An approval covers the action classes the user was actually shown** — those named in the question, its options, and its blast-radius render. Everything else stays unapproved.

**Bound the license to the render, not to how broadly the user answered.** A gate that enumerated two applies and their blast radius grants those two applies, even when the answer is "yes, do it all yourself" — the user agreed to what the render described. A different class (a direct cluster write, a provisioned instance, an outward post) was never described, so it sits outside the grant. Narrating an action beforehand is disclosure, not consent.

**A new action class opens a new gate.** Render the new class's own blast radius and ask again. A second gate costs one turn; a class the user never saw is the one that surprises them.

**An instruction naming one outward action authorizes that action, plus whatever its effect already contains.** "Merge to develop" authorizes the merge, and a still-pending push of the branch that merge consumes rides along — landing that code on `develop` is the larger effect, so gating the smaller enabling step would re-ask for less than the user just granted. Containment reaches forward only: an outward action already taken was unapproved when it ran, and a later instruction does not reach back to cover it. An outward action whose effect is NOT already contained in the approved one carries its own approval: a second push after the merge, a release tag, an outward post, a deploy trigger — each inside the same task and the same turn.

**An under-specified instruction re-opens the gate rather than expanding to fill it.** A bare "open PR" with no draft-versus-ready qualifier fires the ship-mode gate rather than overriding it (`${CLAUDE_PLUGIN_ROOT}/skills/implement/implement-reference.md` §"Step 4 — Ship-mode AUQ"). Missing detail is a question, not a blank to fill with the widest reading.

**Measure each outward action against its own approval, never against accumulated trust.** Approval does not compound across a session — three granted gates do not make the fourth implicit.

**Outward means it leaves this machine or becomes visible to someone else** — a push, a pull request, a posted comment, a tracker transition, a deploy. A local commit is none of those: it reaches nobody and stays revertible in-tree, so it is the run's own bookkeeping and needs no gate. Gate the push that would publish those commits instead. Counting the commit as outward turns "I have an uncommitted diff" into a standing reason to hand the run back after every green check.

**Reversibility is not the test — authorship is.** A gate exists because the choice is the user's, not because the action would be hard to undo. A small blast radius is an argument for asking briefly, never for not asking.

## Invocation-scoped approval (`/geniro:actions run`)

Invoking an action IS its approval — `/geniro:actions run <slug>` executes the action's steps directly and fires no confirmation, because re-asking would repeat the decision the user already made by invoking it. The rule above names that grant's boundary rather than adding a gate to it: the invocation authorizes the action **as its own definition declares it** — its documented steps, its `allowed-tools`, its declared side effects. An outward effect beyond that declared scope was not part of what the user invoked, so it carries its own approval.

## Anti-rationalization

| Rationalization | Why it is wrong |
|---|---|
| "The user said 'yes, do it all yourself' — that covers whatever the task needs." | It covers the classes the question and its blast-radius render named. A broad answer widens confidence, not scope. Render the unshown class and ask again. |
| "I said I was about to provision it and the user didn't object." | Narration is disclosure, not consent — silence mid-run is not a pick. Fire the gate for the new class. |
| "They asked me to merge, so tagging the release it produces is implied." | Containment runs one way: the merge contains the push that feeds it, never the tag that follows it. A tag, a deploy trigger, and an outward post are separate actions with their own blast radius; "merge to develop" answers for the merge. |
| "They approved the last three pushes — this one is obviously fine." | Approval does not compound across a session. Measure this action against its own gate, not against accumulated trust. |
| "Creating the branch is safe and reversible, and standard practice on a protected branch — I'll skip asking and just do it." | Standard practice says what a sensible default looks like, not who picks it. Worktree, current branch, a different slug — each stays invisible until asked, and "they can undo it" hands the user work the gate would have avoided. |
| "Asking again for a near-identical action is annoying." | It is near-identical only in your reading — the user never saw the new class's blast radius. One extra turn beats an unapproved mutation the user has to undo. |
