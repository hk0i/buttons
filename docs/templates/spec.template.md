<!-- Save as docs/slices/NN. Slice Name.spec.md — NN matches the EDD roadmap
step this implements. Bounded, literal, disposable: a work ticket, not a
lasting reference. -->

# Slice Spec: [Slice Name]

| | |
|---|---|
| **Doc Type** | Slice Spec |
| **Author** | [Name] |
| **Date** | [YYYY-MM-DD] |
| **Status** | Draft |
| **Reviewers** | [Names, or "—"] |

**Implements:** [EDD filename], Testing & Rollout Plan step [N].
**TL;DR:** [1 sentence: what this slice proves, end-to-end.]

> **Style:** terse over complete — cut words that don't carry a decision,
> fact, or constraint. Write for a human skimming and an agent executing:
> concrete nouns, exact names, exact commands, not vague gestures at intent.
> Use a Mermaid diagram instead of prose for any multi-step exchange.

---

## Scope

**In:** [Exactly what this slice does. Bullet list, no ambiguity.]

**Out:** [Explicitly excluded — especially anything adjacent that would be
tempting to also do while in here. This is the scope fence.]

> **Rule for agent:** stay inside this scope. If something out of scope
> blocks you, stop and flag it — don't silently expand scope to route around
> it.

## Files to Touch

- `path/to/file` — [create/modify] — [one line: what changes]

> **Rule for agent:** don't touch files outside this list without flagging
> it first.

## Interface / Data Contract

[Exact shapes touched by this slice — message fields, function signatures,
schema fragments. Copy the relevant fragment from the EDD rather than
re-deriving it; keep them in sync if it changes here.]

## Implementation Notes *(delete if there's nothing non-obvious to say)*

[Terse, load-bearing notes only — the thing that isn't obvious from the
contract above. Point to the EDD section for rationale instead of repeating
it.]

## Definition of Done

- [ ] [Observable behavior — what you can see/do once this works.]

**Verification:**
```
[exact command(s) to run — build, lint, test]
```

> **Rule for agent:** run the verification command(s) above before declaring
> this slice done. Report the actual output, not an assumption that it
> passed.

## Rollback *(delete if this slice is low-risk enough not to need it)*

[What to revert first if verification fails, and what to re-check before
retrying.]
