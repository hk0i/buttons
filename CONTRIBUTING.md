# Contributing

Thanks for your interest in this project. A few rules keep the licensing clean —
please read this before opening a pull request.

## Developer Certificate of Origin (DCO)

Every commit must be signed off. This certifies that you wrote the contribution
(or otherwise have the right to submit it under the license below). Add the
sign-off with `-s`:

```
git commit -s -m "your message"
```

which appends a line to the commit message:

```
Signed-off-by: Your Name <your.email@example.com>
```

The name and email must be real and must match your commit author identity.
By signing off you agree to the Developer Certificate of Origin 1.1:

```
Developer Certificate of Origin
Version 1.1

Copyright (C) 2004, 2006 The Linux Foundation and its contributors.

Everyone is permitted to copy and distribute verbatim copies of this
license document, but changing it is not allowed.

Developer's Certificate of Origin 1.1

By making a contribution to this project, I certify that:

(a) The contribution was created in whole or in part by me and I
    have the right to submit it under the open source license
    indicated in the file; or

(b) The contribution is based upon previous work that, to the best
    of my knowledge, is covered under an appropriate open source
    license and I have the right under that license to submit that
    work with modifications, whether created in whole or in part
    by me, under the same open source license (unless I am
    permitted to submit under a different license), as indicated
    in the file; or

(c) The contribution was provided directly to me by some other
    person who certified (a), (b) or (c) and I have not modified
    it.

(d) I understand and agree that this project and the contribution
    are public and that a record of the contribution (including all
    personal information I submit with it, including my sign-off) is
    maintained indefinitely and may be redistributed consistent with
    this project or the open source license(s) involved.
```

We do not use a CLA. Copyright in your contribution stays with you; you license
it to the project under the terms below (inbound = outbound). No copyright
assignment, no relicensing rights are transferred.

## Which license your contribution falls under

This repository is licensed **per top-level directory**. Your contribution to a
directory is offered under that directory's license, the same terms the rest of
that directory carries. The root `LICENSE` file is the authoritative map:

| Directory | License | Terms file |
|---|---|---|
| `desktop/` | GPL-3.0-only | `desktop/LICENSE` |
| `ios/` | MIT | `ios/LICENSE` |
| `android/` | MIT | `android/LICENSE` |
| `protocol/` | MIT for schema/code (`*.proto`, code); CC BY 4.0 for prose (`*.md`) | `protocol/LICENSE`, `protocol/LICENSE-docs` |
| `docs/` | CC BY-SA 4.0 | `docs/LICENSE` |
| `spikes/` | MIT (exploratory throwaway code) | root `LICENSE` |
| repo root (this file, `.github/`, tooling) | MIT | root `LICENSE` |

`docs/` is share-alike (CC BY-SA 4.0): if you adapt or extend the design
documents, your changes carry the same license. If you want a design idea
implemented in permissively-licensed code, describe it and let it be
reimplemented — ideas aren't copyrightable, only the specific wording is.

The normative wire-protocol specification lives in `protocol/`, deliberately
under permissive terms so third-party implementations aren't encumbered. Keep
protocol *specification* changes in `protocol/`; `docs/` holds rationale and
discussion.

## Pull requests

1. Keep changes small and focused — one logical change per PR.
2. Match the surrounding code's style and conventions.
3. If a change touches behavior, say how you verified it.
4. Design-level changes: open an issue or discussion first, and expect the
   relevant `docs/` file to be updated as part of the PR.
5. Swift changes: run `swift-format lint` first — see § Code formatting
   (Swift). No CI enforcement yet, so this is on the contributor.

## Documentation style

Numbered lists (`1.`, `2.`, ...) are the default list style in all docs in
this repo — `docs/`, this file, `protocol/`, `spikes/` READMEs — not `-`
bullets. Decided 2026-09-11.

**Why:** a number is a stable pointer into an otherwise-unordered list of
points — "see point 4" instead of restating the point's content to refer to
it. That property holds in conversation, in review comments, and across a
diff.

**Rule: every list restarts at `1.`.** A `**Bold Label**` or `###` heading
that introduces a new sub-group of items starts a new list — never continue
a global count across it (`1,2,3` then, under the next label, `4,5` instead
of restarting at `1,2`). Some renderers fail to render an ordered list at
all when its first item's number is greater than 1, and a restarting-per-
group list carries no less information than a globally-numbered one, since
nothing in this repo cites one of these items by its number.

**Known costs, accepted anyway:**

1. Inserting or removing an item renumbers everything after it, touching
   lines that didn't otherwise change.
2. That renumbering adds diff noise beyond the actual edit.

Decision: the random-access-pointer benefit outweighs both costs. Numbered
lists are the standard going forward, full stop — including new lists in
existing docs, not just new docs.

**Bold vs. heading.** A standalone line that labels the block of content
beneath it is a heading (`#`, one level below its parent) — not bold text.
Bold is for a label/value lead-in inline with its value (`**Verification:**`
followed by the content) or emphasis inside running prose. A bold-only line
introducing its own sub-section (e.g. a tier, a component, a Goals/
Non-Goals split) belongs in the document's outline/TOC, which only a real
heading gives it.

## Doc comments (code)

Decided 2026-09-12, per slice 07 review. Applies to `///` (Swift, Rust) /
`/** */` (Kotlin, TypeScript) doc comments — not `//`/`/* */` implementation
comments, which this doesn't constrain.

1. Summary is one sentence: third-person verb, ends with a period. Don't
   restate what the signature already says.
2. Use the language's structured fields instead of a prose paragraph —
   Swift: `- Parameter:`, `- Returns:`, `- Throws:`, `- Note:`, `- Important:`.
   Rust: `# Arguments`, `# Returns`, `# Panics`. Tooling (Xcode Quick Help
   and Swift-DocC, `cargo doc`) renders these distinctly; an undifferentiated
   paragraph just becomes a wall of text.
3. Rationale belongs in a `//` comment, not the doc comment — why an
   alternative was rejected, a bug this fixes, the reasoning behind a
   non-obvious choice. The doc comment is the contract for a caller; `//`
   is the argument for whoever reads the diff next, and for stopping a
   future "fix" of something that isn't broken.

   **State the invariant; cite an immutable artifact, never a position in a
   living document.** `// Implementation Notes #10.2` breaks the moment
   anyone inserts a note above it — same failure this file's own
   Documentation-style rule (numbered lists restart per group *because*
   nothing should cite an item by ordinal) already rejects for prose; a `//`
   comment isn't exempt. In preference order:
   1. State the reason inline, cite nothing (`// Local Network permission
      has no pre-check API — denial makes traffic vanish silently.`). Holds
      up even if the spec is rewritten or archived; usually all a comment
      needs.
   2. Reason inline, plus a pointer only when the full argument is long
      enough to genuinely live elsewhere — cite the spec section **by
      heading text**, not ordinal (`docs/slices/07…, § Implementation
      Notes, "Two permissions, two different shapes"`). Section headings
      (`## Implementation Notes`) are template-fixed and stable; item
      numbers inside them aren't.
   3. A commit SHA, for "this line is load-bearing, here's the change that
      proved it" (`// Fixed in 5bef681 — …`). Immutable by construction.

   A spec/issue *link* is still exactly right in a PR description — a
   reviewer needs it during review. A maintainer six months later needs the
   reason, not a click-through, which is why the two don't share a home.
4. Naming rationale — why this name and not an obviously-confusable one —
   belongs in the slice spec / EDD, not in code, unless the name is
   genuinely likely to be misused by someone unfamiliar with the codebase.
   Decide names during doc planning; when a better name surfaces mid-
   implementation instead, change it in code and update the spec/EDD
   retroactively rather than stranding the reasoning in a code comment.
5. Link symbol names with backticks (`` `TypeName` ``) — Swift-DocC and
   rustdoc both turn these into jump-links once docs are actually built.
6. If the summary line explains the function better than its name does,
   rename the function and shorten (or delete) the summary. A summary that
   merely restates the identifier is dead weight; a summary that's *more
   precise* than the identifier means the identifier is underspecified —
   move the precision into the name. Applies to the summary line only:
   preconditions, nil/empty semantics, side effects, and thread
   requirements often can't live in a name and stay in `- Parameter:` /
   `- Returns:` / `- Note:`. Stopping condition: if the name would need
   more than a few words to carry the meaning, the meaning belongs in the
   comment — prefer argument labels (`endpoint(forDeviceId:)`) over a
   longer base name.

**Not done yet:** a repo-wide pass bringing existing comments to this style
— planned as a follow-up, not blocking work in progress. New and
touched-in-passing comments follow this style starting now.

## Code formatting (Swift)

Decided 2026-09-13. `ios/` uses [apple/swift-format](https://github.com/apple/swift-format)
(bundled with the Xcode toolchain — `xcrun swift-format`, no separate
install), configured by `.swift-format` at the repo root.

1. **Run before committing:**
   ```
   xcrun swift-format lint --configuration .swift-format -r ios/Buttons
   xcrun swift-format format --configuration .swift-format -i -r ios/Buttons
   ```
   `lint` reports violations without changing files; `format -i` rewrites
   them in place. No CI enforcement yet — this is a manual step, same as
   every other verification command in this repo's slice specs.
2. **4-space indent, not the tool's 2-space default.** The 2-space default
   is inherited from Google's published Swift style guide (the guide
   Apple's own formatter took its defaults from), not a separate Apple
   mandate — Xcode's own editor default, and most existing code in this
   repo, is 4-space. Tried a full 2-space repo reformat first; reverted
   (2026-09-13) after review — revisit only with a concrete reason, not by
   default.
3. **`UseLetInEveryBoundCaseVariable` disabled.** Default style rewrites
   `case let .foo(a, b, c)` to `case .foo(let a, let b, let c)` — this repo
   prefers the single-`let` form for a multi-value pattern; less repeated
   noise on the line.
4. **No leading-operator line wrapping.** Wanted continuation lines to
   break *before* an operator (`let message\n    = ...`) so operators
   stack in the left column — confirmed against the tool's own
   `Configuration.md` that no such option exists; wrap position isn't
   configurable, only the pretty-printer's fixed trailing-operator style is
   available. Not worth hand-formatting around — accepted as a real tool
   limitation, not revisited without a new upstream capability.
5. **Kotlin/Rust have no equivalent tool wired up yet.** `desktop/` and any
   future `android/` code isn't covered by this section.
