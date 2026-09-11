# protocol

`buttons.proto` is the data-model schema (`Config`/`Profile`/`Page`/`Button`/
`Action`) — the single source of truth, translating the shape
`desktop/src/lib/types/button.ts` and `ios/Buttons/Models/ButtonModel.swift`
validated in slices 2-5. See
`docs/slices/06. Protobuf Codegen Prototype.spec.md` for the full design
rationale and the deliberate findings this schema produced, and
`docs/01. Architecture Overview.edd.md` for the wider architecture.

`verify-rust/`, `verify-swift/`, `verify-kotlin/` are standalone codegen +
round-trip prototype packages (`prost`, `swift-protobuf`, `com.squareup.wire`
respectively) — they prove the schema generates and compiles in all three
target languages before anything in `/desktop`, `/ios`, or `/android`
depends on it (that's roadmap step 7, and step 12 for Android). Run
`cargo test` / `swift test` / `gradle test` in each to verify.

**Wire envelope messages** (`pair_request`, `config_sync`, `button_press`,
etc.) aren't in `buttons.proto` yet — those get designed at step 7 alongside
the real connection code, not guessed at here.

This directory is also the home for the **normative wire-protocol
specification** — the message catalog, field shapes, and pairing sequence.
The EDD in `docs/` holds the rationale and design discussion and refers here
for the canonical shapes.

## Licensing

Two licenses apply here, by file type:

1. **Schema and code** (`*.proto`, generated or hand-written code) — MIT, see
   `LICENSE`.
2. **Prose** (`*.md`, including this file and any specification written as
   prose) — CC BY 4.0, see `LICENSE-docs`.

Both are permissive with attribution — deliberately, so third-party
implementations of the protocol carry no copyleft obligation. This differs
from `docs/`, which is CC BY-SA 4.0 (share-alike).
