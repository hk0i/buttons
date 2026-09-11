# Network POC (Spike)

This is a throwaway spike, **not** part of the shipped product. It exists to
prove desktop mDNS-advertise + iOS mDNS-discover + a two-way WebSocket message
exchange works on a real LAN, that the protobuf toolchain works across
Rust/Swift, and that a terminal QR code can be rendered from a Tauri-less Rust
CLI.

See `docs/slices/00. Network POC Spike.spec.md` for the full spec, scope, and
definition of done.

It is kept in the repo afterward only as an unmaintained reference — do not
wire it into `/desktop`, `/ios`, `/android`, or `/protocol`.

## Manually testing the desktop server with `websocat`

`websocat` (`brew install websocat`) is a generic WebSocket CLI client, useful
for poking at the desktop binary without a real mobile client.

Run the desktop binary in one terminal:

```
cd spikes/network-poc/desktop
cargo run
```

In another terminal, connect and receive the desktop's `Ping`:

```
websocat ws://<desktop-ip>:8765
```

This prints the raw bytes of the `Ping` protobuf message the desktop sends on
connect (something like `\n\x1eHello from Buttons desktop POC`) — it won't be
decoded, since `websocat` doesn't know about our `.proto` schema.

To send a `Ping` back (exercising the desktop's receive/log path), hand-encode
the protobuf bytes and pipe them in as a **binary** frame:

```
printf '\x0a\x05hello' | websocat -b --one-message ws://<desktop-ip>:8765
```

1. `\x0a` — protobuf tag byte for field 1 (`text`), wire type 2 (length-delimited)
2. `\x05` — length of the string that follows, as a single-byte varint
3. `hello` — the UTF-8 text; update the length byte to match if you change it

`-b` sends the input as one binary WebSocket frame instead of line-buffered
text — this matters because the tag byte `0x0a` is also an ASCII newline, so
without `-b` `websocat` would misread it as a line break. This only works for
strings under 128 bytes (single-byte varint length); longer strings need a
2-byte varint length prefix instead.
