<script lang="ts">
  import type { Button as ButtonModel } from "$lib/types/button";
  import { buttonStore } from "$lib/stores/buttons.svelte";

  let { button, onClose }: { button: ButtonModel | null; onClose: () => void } = $props();

  let label = $state(button?.label ?? "");
  let icon = $state(button?.icon ?? "");

  async function save() {
    await buttonStore.save({
      id: button?.id ?? crypto.randomUUID(),
      label: label || undefined,
      icon: icon || undefined,
      actions: button?.actions ?? [],
    });
    onClose();
  }

  async function remove() {
    if (button) {
      await buttonStore.remove(button.id);
    }
    onClose();
  }
</script>

<div
  class="overlay"
  role="presentation"
  onclick={onClose}
  onkeydown={(e) => e.key === "Escape" && onClose()}
>
  <div
    class="panel"
    role="dialog"
    aria-modal="true"
    tabindex="-1"
    onclick={(e) => e.stopPropagation()}
  >
    <h2>{button ? "Edit Button" : "Add Button"}</h2>
    <label>
      Icon
      <input type="text" bind:value={icon} placeholder="🔘" maxlength="4" />
    </label>
    <label>
      Label
      <input type="text" bind:value={label} placeholder="Button label" />
    </label>
    <div class="actions">
      {#if button}
        <button type="button" class="danger" onclick={remove}>Delete</button>
      {/if}
      <button type="button" onclick={onClose}>Cancel</button>
      <button type="button" onclick={save}>Save</button>
    </div>
  </div>
</div>

<style>
  .overlay {
    position: fixed;
    inset: 0;
    background: rgba(0, 0, 0, 0.4);
    display: flex;
    align-items: center;
    justify-content: center;
  }

  .panel {
    background: #ffffff;
    color: #0f0f0f;
    border-radius: 12px;
    padding: 20px;
    min-width: 260px;
    display: flex;
    flex-direction: column;
    gap: 12px;
  }

  label {
    display: flex;
    flex-direction: column;
    gap: 4px;
    font-size: 0.85rem;
    text-align: left;
  }

  input {
    border-radius: 8px;
    border: 1px solid rgba(0, 0, 0, 0.2);
    padding: 0.5em 0.75em;
    font-size: 1em;
  }

  .actions {
    display: flex;
    justify-content: flex-end;
    gap: 8px;
    margin-top: 8px;
  }

  .danger {
    margin-right: auto;
    color: #c0392b;
  }

  @media (prefers-color-scheme: dark) {
    .panel {
      background: #2f2f2f;
      color: #f6f6f6;
    }

    input {
      background: #0f0f0f98;
      border-color: rgba(255, 255, 255, 0.2);
      color: #f6f6f6;
    }
  }
</style>
