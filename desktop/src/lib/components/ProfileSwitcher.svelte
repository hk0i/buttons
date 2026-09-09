<script lang="ts">
  import { configStore } from "$lib/stores/config.svelte";

  // Neither window.prompt() nor window.confirm() work in Tauri's WKWebView
  // without a native panel delegate the host wires up — prompt() renders
  // nothing, and confirm() silently returns true (so a guarded destructive
  // action fires with no dialog). Both the name inputs and the delete
  // are-you-sure below are therefore inline UI, same substitute pattern.
  let editing = $state<"create" | "rename" | "delete" | null>(null);
  let draftName = $state("");

  function startCreate() {
    editing = "create";
    draftName = "";
  }

  function startRename() {
    const profile = configStore.activeProfile;
    if (!profile) return;
    editing = "rename";
    draftName = profile.name;
  }

  function cancelEdit() {
    editing = null;
    draftName = "";
  }

  function confirmEdit() {
    const name = draftName.trim();
    if (!name) return cancelEdit();
    if (editing === "create") {
      configStore.createProfile(name);
    } else if (editing === "rename") {
      const profile = configStore.activeProfile;
      if (profile) configStore.renameProfile(profile.id, name);
    }
    cancelEdit();
  }

  function focusOnMount(node: HTMLInputElement) {
    node.focus();
  }

  function startDelete() {
    if (!configStore.activeProfile) return;
    editing = "delete";
  }

  function confirmDelete() {
    const profile = configStore.activeProfile;
    if (profile) configStore.deleteProfile(profile.id);
    cancelEdit();
  }
</script>

<div class="profile-switcher">
  {#if editing === "delete"}
    <span class="delete-prompt">Delete "{configStore.activeProfile?.name}"?</span>
    <button type="button" class="danger" onclick={confirmDelete} title="Confirm delete">✓</button>
    <button type="button" onclick={cancelEdit} title="Cancel">✕</button>
  {:else if editing}
    <input
      type="text"
      bind:value={draftName}
      placeholder="Profile name"
      use:focusOnMount
      onkeydown={(e) => {
        if (e.key === "Enter") confirmEdit();
        else if (e.key === "Escape") cancelEdit();
      }}
    />
    <button type="button" onclick={confirmEdit} title="Confirm">✓</button>
    <button type="button" onclick={cancelEdit} title="Cancel">✕</button>
  {:else}
    <select
      value={configStore.activeProfile?.id}
      onchange={(e) => configStore.switchProfile(e.currentTarget.value)}
    >
      {#each configStore.config?.profiles ?? [] as profile (profile.id)}
        <option value={profile.id}>{profile.name}</option>
      {/each}
    </select>
    <button type="button" onclick={startCreate} title="New profile">+</button>
    <button type="button" onclick={startRename} title="Rename profile">✎</button>
    <button
      type="button"
      class="danger"
      onclick={startDelete}
      disabled={(configStore.config?.profiles.length ?? 0) <= 1}
      title="Delete profile"
    >
      ×
    </button>
  {/if}
</div>

<style>
  .profile-switcher {
    display: flex;
    align-items: center;
    gap: 6px;
  }

  select,
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
    height: 28px;
    box-sizing: border-box;
  }

  button {
    background: var(--neutral-600);
    border: 1px solid var(--neutral-700);
    color: var(--key-white);
    border-radius: 4px;
    width: 28px;
    height: 28px;
    flex-shrink: 0;
    font-family: var(--font-body);
    font-size: 12px;
    cursor: pointer;
  }

  button.danger:not(:disabled) {
    color: #ff8a75;
  }

  .delete-prompt {
    flex: 1;
    min-width: 0;
    font-family: var(--font-body);
    font-size: 12px;
    color: var(--key-white);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  button:disabled {
    opacity: 0.4;
    cursor: default;
  }
</style>
