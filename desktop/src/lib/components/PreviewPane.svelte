<script lang="ts">
  import { invoke } from "@tauri-apps/api/core";
  import { configStore } from "$lib/stores/config.svelte";
  import DeckButton from "./DeckButton.svelte";
  import ProfileSwitcher from "./ProfileSwitcher.svelte";
  import PagePager from "./PagePager.svelte";
  import type { Button as ButtonModel } from "$lib/types/button";

  let {
    selectedId,
    onSelect,
    onAdd,
    onNavigate,
    orientation = $bindable("portrait"),
  }: {
    selectedId: string | undefined;
    onSelect: (button: ButtonModel) => void;
    onAdd: () => void;
    onNavigate: () => void;
    orientation: "portrait" | "landscape";
  } = $props();

  let draggedId = $state<string | null>(null);

  function onDrop(targetId: string) {
    if (!draggedId || draggedId === targetId) return;
    const buttons = configStore.visibleButtons;
    // buttons[0] is always Back once we're inside a folder — never a valid
    // drop target, since nothing may land ahead of it.
    if (buttons[0]?.content.type === "back" && targetId === buttons[0].id) return;
    const ids = buttons.map((b) => b.id);
    const fromIndex = ids.indexOf(draggedId);
    const toIndex = ids.indexOf(targetId);
    ids.splice(fromIndex, 1);
    ids.splice(toIndex, 0, draggedId);
    draggedId = null;
    configStore.reorderButtons(ids);
  }

  // Double-click "fires" a cell: run its actions, navigate into a Folder, or
  // navigate up on Back — the same dispatch the editor's own fire affordance
  // (Test / Show Content / Go Back) uses. Either navigation direction closes
  // whatever editor is open — that button lived in the context being left,
  // so it's no longer even in view.
  async function fire(button: ButtonModel) {
    switch (button.content.type) {
      case "actions":
        await invoke("run_actions", { actions: button.content.actions });
        break;
      case "folder":
        configStore.enterFolder(button);
        onNavigate();
        break;
      case "back":
        configStore.exitFolder();
        onNavigate();
        break;
    }
  }
</script>

<div class="preview-pane" class:landscape={orientation === "landscape"}>
  <div class="preview-top">
    <div class="preview-header">
      <span class="preview-label">Preview</span>
      <div class="preview-header-actions">
        <button
          type="button"
          class="orientation-toggle"
          onclick={() => (orientation = orientation === "portrait" ? "landscape" : "portrait")}
        >
          {orientation === "portrait" ? "Portrait" : "Landscape"}
        </button>
        <button type="button" class="add-button" onclick={onAdd}>+ Add</button>
      </div>
    </div>

    <ProfileSwitcher />
  </div>

  <div class="preview-main">
    <div class="phone" class:landscape={orientation === "landscape"}>
      <div class="button-grid">
        {#each configStore.visibleButtons as button (button.id)}
          <div
            class="cell"
            role="group"
            draggable={button.content.type !== "back"}
            ondragstart={(e) => {
              if (button.content.type === "back") return;
              draggedId = button.id;
              e.dataTransfer?.setData("text/plain", button.id);
            }}
            ondragover={(e) => e.preventDefault()}
            ondrop={(e) => {
              e.preventDefault();
              onDrop(button.id);
            }}
          >
            <button
              class="grid-button-wrapper"
              type="button"
              onclick={() => onSelect(button)}
              ondblclick={() => fire(button)}
            >
              <DeckButton
                icon={button.icon ?? (button.content.type === "back" ? "⬅" : undefined)}
                label={button.label ?? (button.content.type === "back" ? "Back" : undefined)}
                selected={button.id === selectedId}
              />
            </button>
          </div>
        {/each}
      </div>
    </div>

    <PagePager />
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

  .preview-top {
    display: flex;
    flex-direction: column;
    gap: 12px;
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

  .preview-pane.landscape .preview-top {
    flex-shrink: 0;
  }

  .preview-pane.landscape .preview-header {
    flex-direction: column;
    align-items: flex-start;
    gap: 8px;
  }

  /* Wraps the grid + pager together so the pager always renders directly
     underneath the grid — the standard pager placement — in both
     orientations, rather than living in the landscape sidebar where it'd
     eat into already-scarce horizontal space. */
  .preview-main {
    display: flex;
    flex-direction: column;
    gap: 8px;
    min-width: 0;
  }

  .preview-pane.landscape .preview-main {
    flex: 1;
    min-height: 0;
  }

  .preview-header-actions {
    display: flex;
    align-items: center;
    gap: 8px;
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

  .add-button {
    background: var(--primary-700);
    border: 1px solid var(--primary-900);
    box-shadow: 2px 2px 2px var(--primary-900);
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
