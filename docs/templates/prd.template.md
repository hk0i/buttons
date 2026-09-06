# PRD: [Product/Feature Name]

| Doc Type | Author | Date | Status | Reviewers |
|---|---|---|---|---|
| PRD | [Name] | [YYYY-MM-DD] | Draft | [Names, or "—"] |

**TL;DR:** [2 sentences: what this is and why it matters. Someone should be
able to read only this line and know what's being built.]

---

## Problem Statement

[1-3 sentences. The exact problem, and why it's worth solving now. No
background essay — if context is needed, one line, not a story.]

## Goals

- [What "done" looks like, as outcomes — not features. One line each.]

## Non-Goals

- [Explicitly out of scope. This section prevents scope creep more than any
  other — be specific, not just "everything else."]

## Competitive Positioning *(delete if not applicable)*

[Who/what this competes with, and 2-4 concrete points of differentiation.
Skip entirely for internal/non-competitive work.]

## Monetization *(delete if not applicable)*

[Only if revenue/pricing is a real product decision here.]

## Target Users

- **[Persona]:** [what they need from this, one line]

## Use Cases

[The concrete scenarios this serves. If use cases vary a lot in build cost,
tier them explicitly (cheapest/no-dependency first) rather than listing them
flat — that tiering *is* your MVP argument.]

## [Core Domain Model] *(rename to fit — e.g. "Data Model," "Button Model")*

[The central concepts/entities this product introduces, stated as facts, not
descriptions. Most likely section to need a diagram — prefer a Mermaid
`classDiagram` or `graph` over paragraphs describing structure.]

## Functional Requirements

**[Component A]**
1. [One behavior per line. Testable — a reader should be able to check it
   off.]

**[Component B]**
1. [Same.]

## Assumptions & Constraints *(rename to fit — e.g. "Network Assumptions")*

[Environmental facts this design depends on, and known risk areas where
those facts might not hold. State the mitigation, or state there isn't one
yet.]

## Success Metrics

- [Measurable or falsifiable. "Feels fast" is not a metric; "under 50ms" is.]

## Decisions

[Resolved questions, one line each: the decision and the one-line reason.
"Why" for choices already made lives here — don't re-litigate elsewhere.]

## Open Questions

- [Only genuinely unresolved items. Give each an owner or a trigger for when
  it gets resolved, not a permanent "TBD."]

## Future Vision *(delete if not applicable)*

[Explicitly out of current scope, kept here only so the current design
doesn't foreclose it later. Short — a pointer, not a spec.]

## Sources

- [Links for any external research this PRD relies on.]

## Next Step

[What happens after this doc — usually "write/update the EDD."]
