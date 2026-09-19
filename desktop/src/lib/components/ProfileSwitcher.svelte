<script lang="ts">
  import { invoke } from "@tauri-apps/api/core";
  import { configStore } from "$lib/stores/config.svelte";
  import { confirm } from "$lib/stores/confirm.svelte";

  interface RunningApp {
    bundleId: string;
    name: string;
  }

  // window.prompt() doesn't render in Tauri's WKWebView (needs a native panel
  // delegate the host isn't wiring up), so the create/rename name inputs below
  // are inline UI rather than a blocking dialog. Delete, which is a yes/no,
  // routes through the shared ConfirmDialog instead — see
  // docs/slices/04a. ConfirmDialog.spec.md.
  let editing = $state<"create" | "rename" | "app-assoc" | null>(null);
  let draftName = $state("");
  let draftBundleId = $state("");
  let runningApps = $state<RunningApp[]>([]);

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

  async function startAppAssoc() {
    const profile = configStore.activeProfile;
    if (!profile) return;
    editing = "app-assoc";
    draftBundleId = profile.associatedAppByPlatform.macos ?? "";
    runningApps = await invoke<RunningApp[]>("list_running_apps");
  }

  function cancelEdit() {
    editing = null;
    draftName = "";
    draftBundleId = "";
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

  function confirmAppAssoc() {
    const profile = configStore.activeProfile;
    if (profile) configStore.setMacAppAssociation(profile.id, draftBundleId || null);
    cancelEdit();
  }

  function focusOnMount(node: HTMLInputElement) {
    node.focus();
  }

  async function deleteProfile() {
    const profile = configStore.activeProfile;
    if (!profile) return;
    const ok = await confirm({
      title: "Delete profile?",
      body: `"${profile.name}" and all its pages will be removed. This can't be undone.`,
      confirmLabel: "Delete",
      destructive: true,
    });
    if (ok) configStore.deleteProfile(profile.id);
  }
</script>

<div class="profile-switcher">
  {#if editing === "create" || editing === "rename"}
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
  {:else if editing === "app-assoc"}
    <select aria-label="App association" bind:value={draftBundleId}>
      <option value="">None</option>
      {#each runningApps as app (app.bundleId)}
        <option value={app.bundleId}>{app.name}</option>
      {/each}
      {#if draftBundleId && !runningApps.some((a) => a.bundleId === draftBundleId)}
        <option value={draftBundleId}>{draftBundleId}</option>
      {/if}
    </select>
    <button type="button" onclick={confirmAppAssoc} title="Confirm">✓</button>
    <button type="button" onclick={cancelEdit} title="Cancel">✕</button>
  {:else}
    <select
      aria-label="Active profile"
      value={configStore.activeProfile?.id}
      onchange={(e) => configStore.switchProfile(e.currentTarget.value)}
    >
      {#each configStore.config?.profiles ?? [] as profile (profile.id)}
        <option value={profile.id}>{profile.name}</option>
      {/each}
    </select>
    <button type="button" onclick={startCreate} title="New profile">+</button>
    <button type="button" onclick={startRename} title="Rename profile">✎</button>
    <button type="button" onclick={startAppAssoc} title="Set app association">🖥️</button>
    <button
      type="button"
      class="danger"
      onclick={deleteProfile}
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

  button:disabled {
    opacity: 0.4;
    cursor: default;
  }
</style>
