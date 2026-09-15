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

**Protobuf code fences: use `` ```protobuf ``, not `` ```proto ``.** Decided
2026-09-15. GitHub renders both identically. The difference is VS Code: the
installed extension (`DrBlury/protobuf-vsc-extension`, successor to the now-
deprecated `vscode-proto3`) registers no Markdown-injection grammar for
either tag, so the editor view highlights neither — but VS Code's built-in
Markdown *preview* uses its own bundled Shiki grammars independent of any
installed extension, and Shiki recognizes `protobuf`, not `proto`. Until a
PR lands upstream adding the missing injection grammar (tracked
separately), `protobuf` is the one tag that gets any highlighting at all
locally. Going forward only — existing docs using `` ```proto `` are not
being retrofitted; update one only if you're already touching that fence
for another reason.

**Bold vs. heading.** A standalone line that labels the block of content
beneath it is a heading (`#`, one level below its parent) — not bold text.
Bold is for a label/value lead-in inline with its value (`**Verification:**`
followed by the content) or emphasis inside running prose. A bold-only line
introducing its own sub-section (e.g. a tier, a component, a Goals/
Non-Goals split) belongs in the document's outline/TOC, which only a real
heading gives it.

**Annotating a code snippet that changes existing code.** Decided
2026-09-14, amended 2026-09-14, 2026-09-15. When a snippet shows a change to something
that already exists — a new field, a new method, a modified signature —
mark each change point with a short numbered `//` comment **on its own
line directly above** the line it refers to, never trailing on the same
line — and never the bare number alone (`// 1.`): pair it with a few
words of context (`// 1. new — in-flight guard`), so the snippet itself
says what changed without making the reader jump to the elaboration list
below just to find out. A trailing comment competes with the code for
the eye at exactly the point a reader most needs to slow down; a
comment-only line reads as a clear "look here" marker before the code it
annotates. Then follow the
snippet with a numbered list (restarts at `1.`, same rule as above) that
elaborates each point in a sentence or two. Makes new code visually
distinct from the unchanged code around it, and keeps the "what changed
and why" next to the snippet instead of buried in prose above it.

```swift
@Observable
final class PairingSession {
    private(set) var autoReconnectState: AutoReconnectState = .idle

    // 1. new — in-flight guard
    var isReconnectInFlight: Bool { autoReconnectState == .searching }

    // 2. becomes async, gains the guard
    func attemptAutoReconnect(discovery: DesktopDiscovery) async {
        guard !isReconnectInFlight else { return }
        // ...
    }
}
```

1. `isReconnectInFlight` — derives from existing state instead of a
   separate flag, so there's one source of truth for both call sites that
   need it.
2. `attemptAutoReconnect` — goes `async`; the new guard at its top makes a
   repeat call a no-op while one is already running.

**Elide unchanged code the annotations don't need.** Keep an unchanged
line only as an anchor — the declaration a new member sits next to, the
`guard` a new line follows. A method body shown in full with zero changes
in it (and nothing in the numbered list pointing inside it) is exactly
the noise this whole convention exists to cut — mark it `// ...` and move
on. Two forms, by position, not by preference: `// ...` at statement/
member level (a skipped loop body, a skipped property); `/* ... */` only
where a comment has to sit inside an expression or a single-line brace
pair (`Group { /* ... */ }` — `// ...` there comments out the closing
brace along with everything else). Don't over-elide, either: the snippet
still has to compile as a plausible shape — keep the type/function
declarations, the attributes that changed, and every line an annotation
actually references; elide the rest.

**Scope: this numbering is local to the snippet and its own list,
immediately adjacent in the same section** — not a cross-file or
cross-section reference. § Doc comments (code)'s ban on citing a living
document by ordinal (item 3 below) still holds for that case; it isn't
in tension with this rule, which never crosses a section boundary. A
snippet showing a shape with nothing pre-existing to distinguish (a fresh
type, a `.proto` fragment with no prior version) doesn't need this —
it's for changes, not every snippet.

**Multiple related files in one section share one snippet and one list,
restarting at `1.` once — never several snippets each silently
continuing the last one's count.** If two files' changes belong together
(e.g. a Rust type and the function that returns it, or a struct and the
wire message it mirrors), put them in one fenced block with a plain `//
file.ext` comment marking where each starts, same as this doc's own
Mobile-side example elsewhere in this repo. Never split them into
separate fences that keep counting up from the last one — the restart
rule applies per fence, and a reader hitting a list item numbered `5.`
after a fence with only two comments in it has no way to know three
numbers went missing before it.

**One blank line between top-level declarations inside a multi-declaration
snippet** — two structs, an `impl` block and the struct it returns,
consecutive `message`s in a `.proto` fragment. Without it, a closing `}`
sitting directly above the next declaration's numbered comment reads as
an indentation error on a first pass, not two separate things — exactly
the confusion this whole annotation convention exists to avoid. Doesn't
apply to a run of genuinely trivial one-line wrapper declarations
presented as a deliberate compact batch (e.g. `message Back {}` sitting
next to other one-liners) — that's a different, already-legible shape;
this rule is for the case a reader could mistake two separate blocks for
one nested inside the other.

**One list item per change point — never a range like `3-4.` to cover
two points with one entry.** Neither Markdown nor HTML's ordered-list
syntax supports a range as an item number; a renderer either drops the
line or mangles the list that follows it. Give every numbered comment
its own list item, even when the explanation is one shared sentence —
write it once under the first number and have the second point say "see
above" or add only what's different, rather than merging the numbers
themselves.

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

   **This ban is scoped to cross-file/cross-section references** — a
   snippet's own inline `// 1.` markers, paired with an elaboration list
   immediately below it in the same section, are a different, accepted
   pattern; see § Documentation style, "Annotating a code snippet that
   changes existing code."
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

## Naming: `Phase` vs `State` (enums)

Decided 2026-09-14. A tiebreaker, not a mandate — neither name is a bug,
this just keeps a type's shape legible from its declaration.

1. **`Phase`** when cases only move forward — a progression, where
   re-entering the sequence starts a new cycle rather than looping within
   the same one.
2. **`State`** when any case can legally follow any other — FSM shape, no
   inherent order.
3. **Ownership doesn't decide it.** Code in this repo may itself advance a
   `Phase`; system-advancement isn't a requirement. (Apple's own
   `GestureState` is system-advanced but named State, because a gesture
   isn't a progression — the same reasoning applies here in reverse.)
4. **Tell for a close call:** a terminal case that isn't the end of the
   progression — a failure branch you retry from, not a completion — means
   the type loops back. That's `State`.
5. **Default to `State` when unsure.** A `Phase` that loops back to its
   own start is misnamed; a `State` that happens to be ordered is merely
   unspecific.

Applied to this repo's current enums: `PairingState`
(`Views/PairingView.swift`) and `AutoReconnectState`
(`Networking/Pairing.swift`) both stay `State` — `PairingState` because
`.failed`/`.scanning`/`.cameraDenied` form a legal cycle, not a one-way
walk; `AutoReconnectState` because it re-enters from `.idle` and retries
from `.notFound` (rule 4's tell). No rename from this decision.

## Naming: `match`/closure error bindings

Decided 2026-09-14, found in slice 08's `server.rs`. Applies across
languages (Rust `match`/`?`, Swift `catch`/`case .failure`, TypeScript
`catch`) — this is an identifier-naming rule, not a language-specific one.

**The rule: a binding's name should be as long as its distance to its use,
and as specific as the number of other bindings in scope it could be
confused with.** A one-line passthrough has zero distance and zero
competitors — keep it short:

```rust
match serde_json::from_str(text) {
    Ok(envelope) => envelope,
    Err(parse_error) => {
        eprintln!("server: malformed Envelope: {parse_error}");
        return None;
    }
}
```

`Ok(envelope) => envelope` could just as well be `Ok(e) => e` — the
success binding carries no information, it's a rename. `Err(parse_error)`
is different: it's *used*, three lines away, in a log line whose whole
point is saying what failed. A bare `Err(e)` there is fine in isolation,
but becomes a real hazard the moment a second, differently-typed error
value is in play nearby (a caught error re-wrapped into a reply payload,
say) — two `e`s of different types and different scopes read as
interchangeable even though they aren't. Name it for what it is
(`parse_error`, `load_error`, `join_error`), not for its type or its
match arm position.

Same reasoning for a closure parameter that survives past the line it's
declared on (`.unwrap_or_else(|e| ...)` spanning a real body) — name it
for what failed (`|join_error|`), not `|e|`.

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
