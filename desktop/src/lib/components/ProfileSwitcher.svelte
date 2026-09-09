<script lang="ts">
  import { configStore } from "$lib/stores/config.svelte";

  function createProfile() {
    const name = prompt("New profile name:");
    if (!name?.trim()) return;
    configStore.createProfile(name.trim());
  }

  function renameProfile() {
    const profile = configStore.activeProfile;
    if (!profile) return;
    const name = prompt("Rename profile:", profile.name);
    if (!name?.trim()) return;
    configStore.renameProfile(profile.id, name.trim());
  }

  function deleteProfile() {
    const profile = configStore.activeProfile;
    if (!profile) return;
    if (!confirm(`Delete profile "${profile.name}"? This cannot be undone.`)) return;
    configStore.deleteProfile(profile.id);
  }
</script>

<div class="profile-switcher">
  <select
    value={configStore.activeProfile?.id}
    onchange={(e) => configStore.switchProfile(e.currentTarget.value)}
  >
    {#each configStore.config?.profiles ?? [] as profile (profile.id)}
      <option value={profile.id}>{profile.name}</option>
    {/each}
  </select>
  <button type="button" onclick={createProfile} title="New profile">+</button>
  <button type="button" onclick={renameProfile} title="Rename profile">✎</button>
  <button
    type="button"
    class="danger"
    onclick={deleteProfile}
    disabled={(configStore.config?.profiles.length ?? 0) <= 1}
    title="Delete profile"
  >
    ×
  </button>
</div>

<style>
  .profile-switcher {
    display: flex;
    align-items: center;
    gap: 6px;
  }

  select {
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
