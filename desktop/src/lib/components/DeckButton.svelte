<script lang="ts">
  import type { Button as ButtonModel } from "$lib/types/button";
  import { switchStatesStore } from "$lib/stores/switchStates.svelte";

  let {
    icon,
    label,
    selected = false,
    button,
  }: { icon?: string; label?: string; selected?: boolean; button?: ButtonModel } = $props();

  // A Switch button's real face is its current state's icon/label, not its
  // own top-level ones (which stay unset — see slice 09 spec, Files to
  // Touch #8). Falls back to the plain props every other caller passes
  // directly (the editor's live-typing preview, PreviewPane's "back" glyph).
  let resolvedIcon = $derived(
    button?.content.type === "switch"
      ? ((switchStatesStore.isOn(button.id) ? button.content.on : button.content.off).icon ?? icon)
      : icon,
  );
  let resolvedLabel = $derived(
    button?.content.type === "switch"
      ? ((switchStatesStore.isOn(button.id) ? button.content.on : button.content.off).label ?? label)
      : label,
  );
</script>

<div class="deck-button" class:selected>
  {#if resolvedIcon}
    <span class="icon">{resolvedIcon}</span>
  {/if}
  {#if resolvedLabel}
    <span class="label">{resolvedLabel}</span>
  {/if}
</div>

<style>
  .deck-button {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 6px;
    width: 100%;
    height: 100%;
    aspect-ratio: 1;
    border-radius: 8px;
    border: 2px solid transparent;
    background-color: var(--neutral-300);
    box-sizing: border-box;
    overflow: hidden;
  }

  .deck-button.selected {
    border-color: var(--primary-700);
  }

  .icon {
    font-size: 1.5rem;
    line-height: 1;
  }

  .label {
    font-size: 0.65rem;
    text-align: center;
    color: var(--secondary-700);
    word-break: break-word;
    padding: 0 4px;
  }
</style>
