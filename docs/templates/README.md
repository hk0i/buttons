# Design Doc Templates

Three doc types, used in sequence: **PRD → EDD → Slice Spec**. Copy the
relevant template into `docs/`, following the conventions below.

## Filename convention

`NN. Title.<type>.md` at the top level of `docs/`. The numeric prefix is
authority/reading order (lower number = read first), not creation order.
Doc types: `.prd.md`, `.edd.md`.

Slice specs live in `docs/slices/`, one file per roadmap step from the EDD's
Testing & Rollout Plan, named `NN. Slice Name.slice.md` where `NN` matches
that step's number in the EDD.

## Order of authority

1. **PRD** — what and why. Product framing, requirements, decisions. The PRD
   wins on product scope — if the EDD or a slice spec conflicts with it,
   update them, not the PRD.
2. **EDD** — how, at a system level. Architecture, protocol, alternatives
   considered, and the vertical-slice roadmap. Derived from the PRD.
3. **Slice Spec** — how, for one unit of work. Written immediately before
   implementing one roadmap slice from the EDD. Bounded, literal, and
   disposable — it's a work ticket, not a lasting reference.

## Shared style rules (all three types)

- **Every doc opens with a header table** — `Doc Type | Author | Date |
  Status | Reviewers` — and a 2-sentence **TL;DR**.
- **Terse over complete.** Cut words that don't carry a decision, a fact, or
  a constraint. If a sentence loses nothing by losing a word, cut the word.
  No throat-clearing ("It's worth noting that…", "In order to…").
- **Write for two readers at once: a human skimming, and an agent
  executing.** Concrete nouns, exact names, exact commands — not vague
  gestures at intent. A human should be able to skim it in minutes; an agent
  should be able to act on it without guessing.
- **Use Mermaid diagrams instead of prose for topology, sequence, or flow.**
  If a sentence is describing "A talks to B, then B tells C," draw it
  instead, in a &#96;```mermaid&#96; block. Save prose for what a diagram
  can't carry: rationale, tradeoffs, constraints.
- **State decisions, not just options.** Where a choice was made, say what
  was chosen and why in one line, not a debate. Keep real alternatives to
  "Alternatives Considered," and keep even that section to options that were
  seriously in contention.
- **An open question is a question, not a hedge.** If the answer is already
  known, it's a Decision. Only list something as open if someone still needs
  to decide it.
