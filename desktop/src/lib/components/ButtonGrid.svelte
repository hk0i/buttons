<script lang="ts">
  import { onMount } from "svelte";
  import { buttonStore } from "$lib/stores/buttons.svelte";
  import ButtonEditor from "./ButtonEditor.svelte";
  import type { Button as ButtonModel } from "$lib/types/button";

  onMount(() => {
    buttonStore.load();
  });

  // undefined = editor closed, null = editing a new button, ButtonModel = editing an existing one
  let editingButton = $state<ButtonModel | null | undefined>(undefined);

  let draggedId = $state<string | null>(null);

  function onDrop(targetId: string) {
    if (!draggedId || draggedId === targetId) return;
    const ids = buttonStore.buttons.map((b) => b.id);
    const fromIndex = ids.indexOf(draggedId);
    const toIndex = ids.indexOf(targetId);
    ids.splice(fromIndex, 1);
    ids.splice(toIndex, 0, draggedId);
    draggedId = null;
    buttonStore.reorder(ids);
  }
</script>

<div class="button-grid">
  {#each buttonStore.buttons as button (button.id)}
    <div
      class="cell"
      role="group"
      draggable="true"
      ondragstart={(e) => {
        draggedId = button.id;
        e.dataTransfer?.setData("text/plain", button.id);
      }}
      ondragover={(e) => e.preventDefault()}
      ondrop={(e) => {
        e.preventDefault();
        onDrop(button.id);
      }}
    >
      <button class="grid-button" type="button" onclick={() => (editingButton = button)}>
        {#if button.icon}
          <span class="icon">{button.icon}</span>
        {/if}
        {#if button.label}
          <span class="label">{button.label}</span>
        {/if}
      </button>
    </div>
  {/each}
  <div class="cell">
    <button
      class="grid-button add-button"
      type="button"
      onclick={() => (editingButton = null)}
    >
      <span class="icon">+</span>
      <span class="label">Add</span>
    </button>
  </div>
</div>

{#if editingButton !== undefined}
  <ButtonEditor button={editingButton} onClose={() => (editingButton = undefined)} />
{/if}

<style>
  .button-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(108px, 1fr));
    padding: 10px;
  }

  .cell {
    padding: 6px;
    box-sizing: border-box;
  }

  .grid-button {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 6px;
    width: 100%;
    aspect-ratio: 1;
    border-radius: 12px;
    border: 1px solid rgba(0, 0, 0, 0.1);
    background-color: #ffffff;
    box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);
    cursor: pointer;
    transition:
      border-color 0.2s,
      background-color 0.2s;
  }

  .grid-button:hover {
    border-color: #396cd8;
  }

  .grid-button:active {
    background-color: #e8e8e8;
  }

  .add-button {
    border-style: dashed;
    background-color: transparent;
    opacity: 0.6;
  }

  .add-button:hover {
    opacity: 1;
  }

  .icon {
    font-size: 1.75rem;
    line-height: 1;
  }

  .label {
    font-size: 0.75rem;
    text-align: center;
    color: inherit;
  }

  @media (prefers-color-scheme: dark) {
    .grid-button {
      background-color: #0f0f0f98;
      border-color: rgba(255, 255, 255, 0.1);
      color: #f6f6f6;
    }

    .grid-button:active {
      background-color: #0f0f0f69;
    }
  }
</style>
