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
