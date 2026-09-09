<script lang="ts">
  import "$lib/styles/tokens.css";
  import { onMount } from "svelte";
  import { configStore } from "$lib/stores/config.svelte";
  import ButtonEditor from "$lib/components/ButtonEditor.svelte";
  import PreviewPane from "$lib/components/PreviewPane.svelte";
  import type { Button as ButtonModel } from "$lib/types/button";

  let selected = $state<ButtonModel | "new" | undefined>(undefined);
  let orientation = $state<"portrait" | "landscape">("portrait");

  onMount(async () => {
    await configStore.load();
  });

  function startAdd() {
    selected = "new";
  }

  function selectById(id: string | undefined) {
    selected = configStore.visibleButtons.find((b) => b.id === id) ?? configStore.visibleButtons[0] ?? undefined;
  }

  function onSaved() {
    selected = undefined;
  }

  function onDeleted() {
    selectById(undefined);
  }

  function onCancelled() {
    selected = undefined;
  }
</script>

<div class="app">
  <header class="app-header">
    <h1>Buttons</h1>
  </header>

  <div class="app-body" class:landscape={orientation === "landscape"}>
    <div class="preview-wrapper">
      <PreviewPane
        selectedId={selected && selected !== "new" ? selected.id : undefined}
        onSelect={(b) => (selected = b)}
        onAdd={startAdd}
        bind:orientation
      />
    </div>

    <div class="editor-pane" class:active={selected !== undefined}>
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
          <p class="empty-state">Select a button in the preview to edit it, or click + Add to create one.</p>
        {/if}
      </div>
    </div>
  </div>
</div>

<style>
  :global(body) {
    margin: 0;
    background: var(--neutral-600);
    color: var(--key-white);
    font-family: var(--font-body);
    user-select: none;
    -webkit-user-select: none;
    cursor: default;
  }

  :global(input),
  :global(textarea) {
    user-select: text;
    -webkit-user-select: text;
    cursor: text;
  }

  .app {
    display: flex;
    flex-direction: column;
    height: 100vh;
  }

  .app-header {
    background: var(--neutral-700);
    padding: 10px 16px;
    flex-shrink: 0;
  }

  .app-header h1 {
    font-family: var(--font-heading);
    font-weight: 700;
    font-size: 24px;
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
    display: flex;
    flex-direction: column;
  }

  .empty-state {
    opacity: 0.7;
    font-size: 16px;
  }

  /* Below this width, the two-column layout gets cramped — fall back to
     showing the editor as a full-screen overlay instead of squeezing it,
     and only when it actually has a button to edit. Otherwise leave it
     out of the layout entirely so the preview gets the full canvas. */
  @media (max-width: 700px) {
    .app-body {
      position: relative;
    }

    .editor-pane:not(.active) {
      display: none;
    }

    .editor-pane.active {
      position: fixed;
      inset: 0;
      top: 46px;
      background: var(--neutral-600);
      z-index: 10;
    }
  }
</style>
