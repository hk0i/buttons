<script lang="ts">
  import { configStore } from "$lib/stores/config.svelte";

  function addPage() {
    configStore.addPage();
  }

  function renamePage(id: string, currentName: string | undefined) {
    const name = prompt("Rename page:", currentName ?? "");
    if (name === null) return;
    configStore.renamePage(id, name);
  }

  function removePage(id: string) {
    configStore.removePage(id);
  }
</script>

<div class="page-tabs">
  {#each configStore.activeProfile?.pages ?? [] as page, index (page.id)}
    <div class="tab" class:active={page.id === configStore.currentPageId}>
      <button type="button" class="tab-select" onclick={() => configStore.selectPage(page.id)}>
        {page.name ?? `Page ${index + 1}`}
      </button>
      <button type="button" class="tab-icon" onclick={() => renamePage(page.id, page.name)} title="Rename page">
        ✎
      </button>
      <button
        type="button"
        class="tab-icon danger"
        onclick={() => removePage(page.id)}
        disabled={(configStore.activeProfile?.pages.length ?? 0) <= 1}
        title="Remove page"
      >
        ×
      </button>
    </div>
  {/each}
  <button type="button" class="tab-add" onclick={addPage} title="Add page">+</button>
</div>

<style>
  .page-tabs {
    display: flex;
    align-items: center;
    gap: 4px;
    overflow-x: auto;
  }

  .tab {
    display: flex;
    align-items: center;
    gap: 2px;
    background: var(--neutral-600);
    border: 1px solid var(--neutral-700);
    border-radius: 4px;
    padding: 2px;
    flex-shrink: 0;
  }

  .tab.active {
    border-color: var(--primary-700);
  }

  .tab-select {
    background: transparent;
    border: none;
    color: var(--key-white);
    font-family: var(--font-body);
    font-size: 12px;
    padding: 4px 6px;
    cursor: pointer;
    white-space: nowrap;
  }

  .tab-icon,
  .tab-add {
    background: transparent;
    border: none;
    color: var(--key-white);
    font-size: 11px;
    width: 20px;
    height: 20px;
    flex-shrink: 0;
    cursor: pointer;
  }

  .tab-icon.danger:not(:disabled) {
    color: #ff8a75;
  }

  .tab-icon:disabled {
    opacity: 0.4;
    cursor: default;
  }

  .tab-add {
    background: var(--neutral-600);
    border: 1px solid var(--neutral-700);
    border-radius: 4px;
    width: 28px;
    height: 28px;
  }
</style>
