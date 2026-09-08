# egui Desktop UI Spike

This is a throwaway spike, **not** part of the shipped product. It rebuilds
slice 2's static button grid in `egui`/`eframe` (no Tauri) to compare against
the Tauri+Svelte approach on responsive grid layout, drag-reorder, custom
widget drawing, and measured idle CPU/GPU footprint.

See `docs/slices/00b. egui Desktop UI Spike.spec.md` for the full spec, scope,
and definition of done.

It is kept in the repo afterward only as an unmaintained reference regardless
of outcome — do not wire it into `/desktop`.
