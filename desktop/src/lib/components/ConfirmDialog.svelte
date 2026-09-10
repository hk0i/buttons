<script lang="ts">
  import { getActiveRequest, resolveActive } from "$lib/stores/confirm.svelte";

  // See docs/slices/04a. ConfirmDialog.spec.md. window.confirm() has no working
  // implementation in Tauri's WKWebView (it silently returns true), so every
  // destructive guard in the app routes through this instead.

  let dialogEl = $state<HTMLDialogElement>();
  const request = $derived(getActiveRequest());

  // Open/close the native <dialog> to follow the store. showModal() gives the
  // backdrop, focus trap, and Esc-to-close for free; it also moves focus to the
  // first focusable descendant — the Cancel button, since it's first in DOM
  // order — which is the safe default for a destructive prompt.
  $effect(() => {
    if (!dialogEl) return;
    if (request && !dialogEl.open) dialogEl.showModal();
    else if (!request && dialogEl.open) dialogEl.close();
  });

  function onCancel(event: Event) {
    // Esc fires `cancel`; preventDefault so the browser doesn't also close the
    // dialog out from under our state, then resolve through the store.
    event.preventDefault();
    resolveActive(false);
  }

  function onBackdropClick(event: MouseEvent) {
    // A click on the backdrop lands on the <dialog> element itself. The element
    // carries no padding (all layout is on .panel) so this can't misfire on a
    // click just outside the visible box.
    if (event.target === dialogEl) resolveActive(false);
  }
</script>

<dialog bind:this={dialogEl} oncancel={onCancel} onclick={onBackdropClick}>
  {#if request}
    {@const opts = request.opts}
    <div class="panel">
      <h2>{opts.title}</h2>
      {#if opts.body}<p>{opts.body}</p>{/if}
      <div class="actions">
        <button type="button" onclick={() => resolveActive(false)}>
          {opts.cancelLabel ?? "Cancel"}
        </button>
        <button
          type="button"
          class={opts.destructive ? "danger" : "primary"}
          onclick={() => resolveActive(true)}
        >
          {opts.confirmLabel ?? (opts.destructive ? "Delete" : "OK")}
        </button>
      </div>
    </div>
  {/if}
</dialog>

<style>
  dialog {
    /* Box only — no padding here, so onBackdropClick can trust event.target. */
    padding: 0;
    border: 1px solid var(--neutral-700);
    border-radius: 8px;
    background: var(--neutral-600);
    color: var(--key-white);
    max-width: 320px;
    width: calc(100vw - 48px);
  }

  dialog::backdrop {
    background: rgb(0 0 0 / 0.5);
  }

  .panel {
    padding: 20px;
    display: flex;
    flex-direction: column;
    gap: 12px;
  }

  h2 {
    margin: 0;
    font-family: var(--font-heading);
    font-weight: 700;
    font-size: 16px;
  }

  p {
    margin: 0;
    font-family: var(--font-body);
    font-size: 13px;
    line-height: 1.4;
  }

  .actions {
    display: flex;
    justify-content: flex-end;
    gap: 8px;
    margin-top: 4px;
  }
</style>
