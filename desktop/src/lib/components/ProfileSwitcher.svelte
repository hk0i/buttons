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
  let editing = $state<"create" | "rename" | null>(null);
  let draftName = $state("");
  let isAutoSwitchSupported = $state(false);
  let runningApps = $state<RunningApp[]>([]);
  let currentAssociation = $state<string | null>(null);

  async function refreshRunningApps() {
    runningApps = await invoke<RunningApp[]>("list_running_apps");
  }

  $effect(() => {
    invoke<boolean>("is_auto_switch_supported").then((supported) => {
      isAutoSwitchSupported = supported;
      if (supported) refreshRunningApps();
    });
  });

  $effect(() => {
    const profileId = configStore.activeProfile?.id;
    if (!profileId || !isAutoSwitchSupported) {
      currentAssociation = null;
      return;
    }
    invoke<string | null>("get_app_association", { profileId }).then((bundleId) => {
      currentAssociation = bundleId;
    });
  });

  async function onAppAssocChange(e: Event & { currentTarget: HTMLSelectElement }) {
    const profileId = configStore.activeProfile?.id;
    if (!profileId) return;
    const bundleId = e.currentTarget.value || null;
    await invoke("set_app_association", { profileId, bundleId });
    currentAssociation = bundleId;
  }

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
  <div class="row">
    {#if editing}
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
        aria-label="Active profile"
        value={configStore.activeProfile?.id}
        onchange={(e) => configStore.switchProfile(e.currentTarget.value)}
      >
        {#each configStore.config?.profiles ?? [] as profile (profile.id)}
          <option value={profile.id}>{profile.name}</option>
        {/each}
      </select>

      {#if isAutoSwitchSupported && configStore.activeProfile}
        <select
          id="app-assoc-select"
          value={currentAssociation ?? ""}
          onfocus={refreshRunningApps}
          onchange={onAppAssocChange}
        >
          <option value="" disabled>Associate with running application...</option>
          <option value="">None</option>
          {#each runningApps as app (app.bundleId)}
            <option value={app.bundleId}>{app.name}</option>
          {/each}
          {#if currentAssociation && !runningApps.some((a) => a.bundleId === currentAssociation)}
            <option value={currentAssociation}>{currentAssociation}</option>
          {/if}
        </select>
      {/if}

      <button type="button" onclick={startCreate} title="New profile">+</button>
      <button type="button" onclick={startRename} title="Rename profile">✎</button>
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
</div>

<style>
  .profile-switcher {
    display: flex;
    flex-direction: column;
    gap: 6px;
  }

  .row {
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
