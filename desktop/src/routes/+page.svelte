<script lang="ts">
  import "$lib/styles/tokens.css";
  import { onMount } from "svelte";
  import { buttonStore } from "$lib/stores/buttons.svelte";
  import ButtonEditor from "$lib/components/ButtonEditor.svelte";
  import PreviewPane from "$lib/components/PreviewPane.svelte";
  import type { Button as ButtonModel } from "$lib/types/button";

  let selected = $state<ButtonModel | "new" | undefined>(undefined);
  let previousSelected = $state<ButtonModel | undefined>(undefined);
  let orientation = $state<"portrait" | "landscape">("portrait");

  onMount(async () => {
    await buttonStore.load();
    if (buttonStore.buttons.length > 0) {
      selected = buttonStore.buttons[0];
    }
  });

  function startAdd() {
    if (selected !== "new") {
      previousSelected = selected;
    }
    selected = "new";
  }

  function selectById(id: string | undefined) {
    selected = buttonStore.buttons.find((b) => b.id === id) ?? buttonStore.buttons[0] ?? undefined;
  }

  function onSaved(id: string) {
    selectById(id);
  }

  function onDeleted() {
    selectById(undefined);
  }

  function onCancelled() {
    selected = previousSelected;
  }
</script>

<div class="app">
  <header class="app-header">
    <h1>Buttons Desktop</h1>
  </header>

  <div class="app-body" class:landscape={orientation === "landscape"}>
    <div class="editor-pane">
      <div class="editor-scroll">
        {#if selected === "new"}
          {#key "new"}
            <ButtonEditor button={null} {onSaved} {onDeleted} {onCancelled} />
          {/key}
        {:else if selected}
          {#key selected.id}
            <ButtonEditor button={selected} {onSaved} {onDeleted} {onCancelled} />
          {/key}
        {:else}
          <p class="empty-state">No buttons yet — add one to get started.</p>
        {/if}
      </div>

      <button type="button" class="add-button" onclick={startAdd}>+ Add button</button>
    </div>

    <div class="preview-wrapper">
      <PreviewPane
        selectedId={selected && selected !== "new" ? selected.id : undefined}
        onSelect={(b) => (selected = b)}
        bind:orientation
      />
    </div>
  </div>
</div>

<style>
  :global(body) {
    margin: 0;
    background: var(--neutral-600);
    color: var(--key-white);
    font-family: var(--font-body);
  }

  .app {
    display: flex;
    flex-direction: column;
    height: 100vh;
  }

  .app-header {
    background: var(--neutral-700);
    padding: 24px;
    flex-shrink: 0;
  }

  .app-header h1 {
    font-family: var(--font-heading);
    font-weight: 700;
    font-size: 34px;
    margin: 0;
    color: var(--key-white);
  }

  .app-body {
    display: flex;
    flex-direction: row;
    flex: 1;
    min-height: 0;
  }

  .app-body.landscape {
    flex-direction: column;
  }

  .editor-pane {
    flex: 1;
    padding: 16px;
    display: flex;
    flex-direction: column;
    gap: 16px;
    overflow-y: auto;
  }

  .preview-wrapper {
    flex: 0 0 380px;
    min-width: 340px;
  }

  .app-body.landscape .preview-wrapper {
    flex: 0 0 auto;
    width: 100%;
    min-width: 0;
  }

  .editor-scroll {
    flex: 1;
  }

  .empty-state {
    opacity: 0.7;
    font-size: 16px;
  }

  .add-button {
    align-self: flex-start;
    background: var(--primary-700);
    border: 1px solid var(--primary-900);
    box-shadow: 2px 2px 2px var(--primary-900);
    color: var(--key-white);
    border-radius: 4px;
    padding: 4px 16px;
    height: 32px;
    font-family: var(--font-body);
    font-weight: 500;
    font-size: 12px;
    cursor: pointer;
  }

  /* Below this width, the two-column layout gets cramped — fall back to
     showing the editor as a full-screen overlay instead of squeezing it. */
  @media (max-width: 700px) {
    .app-body {
      position: relative;
    }

    .editor-pane {
      position: fixed;
      inset: 0;
      top: 82px;
      background: var(--neutral-600);
      z-index: 10;
    }
  }
</style>
