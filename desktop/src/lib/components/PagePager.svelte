<script lang="ts">
  import { configStore, MAX_PAGES } from "$lib/stores/config.svelte";

  // See ProfileSwitcher for why this is an inline input rather than
  // window.prompt() (doesn't render in Tauri's WKWebView).
  let editing = $state(false);
  let draftName = $state("");

  function startRename() {
    const page = configStore.currentPage;
    if (!page) return;
    draftName = page.name ?? "";
    editing = true;
  }

  function cancelEdit() {
    editing = false;
    draftName = "";
  }

  function confirmRename() {
    const page = configStore.currentPage;
    if (page) configStore.renamePage(page.id, draftName);
    cancelEdit();
  }

  function focusOnMount(node: HTMLInputElement) {
    node.focus();
  }

  function addPage() {
    configStore.addPage();
  }

  function removePage() {
    const page = configStore.currentPage;
    if (page) configStore.removePage(page.id);
  }
</script>

<div class="page-pager">
  {#if editing}
    <input
      type="text"
      bind:value={draftName}
      placeholder="Page name"
      use:focusOnMount
      onkeydown={(e) => {
        if (e.key === "Enter") confirmRename();
        else if (e.key === "Escape") cancelEdit();
      }}
    />
    <button type="button" class="pager-icon" onclick={confirmRename} title="Confirm">✓</button>
    <button type="button" class="pager-icon" onclick={cancelEdit} title="Cancel">✕</button>
  {:else}
    <div class="page-numbers">
      {#each configStore.activeProfile?.pages ?? [] as page, index (page.id)}
        <button
          type="button"
          class="page-number"
          class:active={page.id === configStore.currentPageId}
          onclick={() => configStore.selectPage(page.id)}
          title={page.name ?? `Page ${index + 1}`}
        >
          {index + 1}
        </button>
      {/each}
    </div>
    <button
      type="button"
      class="pager-icon"
      onclick={addPage}
      disabled={(configStore.activeProfile?.pages.length ?? 0) >= MAX_PAGES}
      title="Add page"
    >
      +
    </button>
    <button type="button" class="pager-icon" onclick={startRename} title="Rename current page">
      ✎
    </button>
    <button
      type="button"
      class="pager-icon danger"
      onclick={removePage}
      disabled={(configStore.activeProfile?.pages.length ?? 0) <= 1}
      title="Remove current page"
    >
      ×
    </button>
  {/if}
</div>

<style>
  .page-pager {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 6px;
  }

  .page-numbers {
    display: flex;
    align-items: center;
    gap: 3px;
    min-width: 0;
    overflow-x: auto;
  }

  .page-number {
    background: var(--neutral-600);
    border: 1px solid var(--neutral-700);
    color: var(--key-white);
    border-radius: 4px;
    width: 22px;
    height: 22px;
    flex-shrink: 0;
    font-family: var(--font-body);
    font-size: 11px;
    cursor: pointer;
  }

  .page-number.active {
    border-color: var(--primary-700);
    background: var(--primary-700);
  }

  .pager-icon {
    background: var(--neutral-600);
    border: 1px solid var(--neutral-700);
    color: var(--key-white);
    border-radius: 4px;
    width: 24px;
    height: 24px;
    flex-shrink: 0;
    font-family: var(--font-body);
    font-size: 12px;
    cursor: pointer;
  }

  .pager-icon.danger:not(:disabled) {
    color: #ff8a75;
  }

  .pager-icon:disabled {
    opacity: 0.4;
    cursor: default;
  }

  input {
    flex: 1;
    min-width: 0;
    padding: 4px 8px;
    background: var(--neutral-600);
    border: 1px solid var(--neutral-700);
    color: var(--key-white);
    border-radius: 4px;
    font-family: var(--font-body);
    font-size: 12px;
    height: 24px;
    box-sizing: border-box;
  }
</style>
