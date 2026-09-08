<script lang="ts">
  import { buttonStore } from "$lib/stores/buttons.svelte";
  import DeckButton from "./DeckButton.svelte";
  import type { Button as ButtonModel } from "$lib/types/button";

  let {
    selectedId,
    onSelect,
    orientation = $bindable("portrait"),
  }: {
    selectedId: string | undefined;
    onSelect: (button: ButtonModel) => void;
    orientation: "portrait" | "landscape";
  } = $props();

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

<div class="preview-pane" class:landscape={orientation === "landscape"}>
  <div class="preview-header">
    <span class="preview-label">Preview</span>
    <button
      type="button"
      class="orientation-toggle"
      onclick={() => (orientation = orientation === "portrait" ? "landscape" : "portrait")}
    >
      {orientation === "portrait" ? "Portrait" : "Landscape"}
    </button>
  </div>

  <div class="phone" class:landscape={orientation === "landscape"}>
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
          <button class="grid-button-wrapper" type="button" onclick={() => onSelect(button)}>
            <DeckButton icon={button.icon} label={button.label} selected={button.id === selectedId} />
          </button>
        </div>
      {/each}
    </div>
  </div>
</div>

<style>
  .preview-pane {
    background: var(--neutral-800);
    padding: 16px;
    display: flex;
    flex-direction: column;
    gap: 12px;
    width: 100%;
    height: 100%;
    box-sizing: border-box;
  }

  .preview-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
  }

  /* Landscape is height-constrained, not width-constrained — trade the
     header's own row for a left-hand sidebar so the grid's top edge
     lines up with the "Preview" label instead of sitting below it. */
  .preview-pane.landscape {
    flex-direction: row;
    align-items: flex-start;
  }

  .preview-pane.landscape .preview-header {
    flex-direction: column;
    align-items: flex-start;
    gap: 8px;
    flex-shrink: 0;
  }

  .preview-label {
    font-family: var(--font-heading);
    font-weight: 700;
    font-size: 20px;
    color: var(--key-white);
  }

  .orientation-toggle {
    background: var(--neutral-600);
    border: 1px solid var(--neutral-700);
    color: var(--key-white);
    border-radius: 4px;
    padding: 4px 12px;
    height: 28px;
    font-family: var(--font-body);
    font-weight: 500;
    font-size: 12px;
    cursor: pointer;
  }

  .phone {
    background: var(--neutral-600);
    border: 2px solid rgba(0, 0, 0, 0.3);
    border-radius: 8px;
    aspect-ratio: 375 / 812;
    width: 100%;
    min-width: 300px;
    min-height: 300px;
    max-width: 375px;
    margin: 0 auto;
    overflow: auto;
    box-sizing: border-box;
  }

  .phone.landscape {
    aspect-ratio: 812 / 375;
    max-width: none;
    max-height: 50vh;
    width: auto;
    height: 100%;
    margin: 0;
    flex: 1;
    min-width: 0;
  }

  .button-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(80px, 1fr));
    padding: 8px;
  }

  .cell {
    padding: 6px;
    box-sizing: border-box;
  }

  .grid-button-wrapper {
    all: unset;
    display: block;
    width: 100%;
    cursor: pointer;
  }
</style>
