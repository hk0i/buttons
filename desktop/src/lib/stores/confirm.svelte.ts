// A single app-themed confirmation dialog, driven by module-level state so any
// call site can `await confirm({ ... })` without wiring props through the tree.
// Exactly one <ConfirmDialog> instance renders this — mounted in +layout.svelte.
// See docs/slices/04a. ConfirmDialog.spec.md.

export interface ConfirmOptions {
  title: string;
  body?: string; // plain text; rendered as textContent, never HTML
  confirmLabel?: string; // default "OK", or "Delete" when destructive
  cancelLabel?: string; // default "Cancel"
  destructive?: boolean; // default false — styles the confirm button as danger
}

interface PendingRequest {
  opts: ConfirmOptions;
  resolve: (result: boolean) => void;
}

// Reassigned $state can't be exported directly — expose it through a getter so
// consumers stay reactive across the module boundary.
let active = $state<PendingRequest | null>(null);

export function getActiveRequest(): PendingRequest | null {
  return active;
}

/**
 * Show a modal confirmation. Resolves true on confirm, false on cancel / Esc /
 * backdrop dismiss. Only one dialog at a time: a call made while another is
 * already open resolves false immediately — dialogs are modal and block
 * interaction, so this path is nearly unreachable in practice.
 */
export function confirm(opts: ConfirmOptions): Promise<boolean> {
  if (active) return Promise.resolve(false);
  return new Promise<boolean>((resolve) => {
    active = { opts, resolve };
  });
}

/** Called by <ConfirmDialog> when the user confirms, cancels, or dismisses. */
export function resolveActive(result: boolean): void {
  if (!active) return;
  active.resolve(result);
  active = null;
}
