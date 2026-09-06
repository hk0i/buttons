# EDD: [System/Feature Name]

| Doc Type | Author | Date | Status | Reviewers |
|---|---|---|---|---|
| EDD | [Name] | [YYYY-MM-DD] | Draft | [Names, or "—"] |

**TL;DR:** [2 sentences: the chosen solution, one level more technical than
the PRD's TL;DR. Point to the PRD for product rationale.]

---

## 1. Purpose & Objective

**Context:** [1-2 sentences: what system this describes; point to the PRD for
full product framing.]

**Problem Statement:** [The technical problem this doc solves — narrower than
the PRD's, focused on *how*, not *why*.]

## 2. Goals & Non-Goals

**Goals** *(technical, derived from the PRD)*
- [...]

**Non-Goals**
- [...]

## 3. Background & Motivation *(delete if there's no real history to record)*

[Only if this doc supersedes an earlier version, or a decision reversed
course. Don't pad this section to look thorough.]

## 4. High-Level Overview

[One paragraph: the chosen solution in plain terms. A stack/component table
if useful, then a system-context Mermaid diagram — the diagram should make
the paragraph's last sentence unnecessary to prove.]

```mermaid
graph LR
  A["Component A"] -- protocol --> B["Component B"]
```

## 5. Detailed Design

*(Use only the subsections that earn their place — delete the rest.)*

### 5.1 [Protocol / Discovery / the hard technical problem]

[Prefer a Mermaid `sequenceDiagram` over describing a multi-step exchange in
prose.]

### 5.2 APIs & Data Models

[Concrete message/interface shapes. A table beats a paragraph.]

### 5.3 Infrastructure & Storage

[Where data lives. State the decision and the one-line reason — put a longer
survey in Alternatives Considered if it's needed.]

### 5.4 Performance & Scale

[Concrete targets, and what they're feasible relative to. Don't state a
number with no reasoning attached.]

### 5.5 Components

[Break down by deployable/buildable unit — what each one owns.]

## 6. Alternatives Considered

- **[Option]:** rejected/deferred — [one line why].

## 7. Cross-Cutting Concerns

**Security & Privacy:** [...]

**Observability:** [What gets logged/monitored, and what's explicitly TBD —
don't invent metrics/dashboards this project doesn't need yet.]

**Testing & Rollout Plan:** [The vertical-slice roadmap lives here — each
slice independently runnable/testable end-to-end, not grouped by
architectural layer. Number them; each becomes a Slice Spec when it's time to
build it.]

1. [Slice name] — [what it proves, in one line].

## Open Questions

- [Same rule as the PRD: only real unresolved items.]

## Sources

[Link to the PRD; add anything else this doc specifically relies on.]
