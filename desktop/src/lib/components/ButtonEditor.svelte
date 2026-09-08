<script lang="ts">
  import { invoke } from "@tauri-apps/api/core";
  import type { Action, Button as ButtonModel, MediaKeyKind } from "$lib/types/button";
  import { buttonStore } from "$lib/stores/buttons.svelte";

  let { button, onClose }: { button: ButtonModel | null; onClose: () => void } = $props();

  let label = $state(button?.label ?? "");
  let icon = $state(button?.icon ?? "");
  let actions = $state<Action[]>(button?.actions ?? []);

  let newActionType = $state<Action["type"]>("launchApp");
  let newPath = $state("");
  let newKeys = $state("");
  let newMediaKey = $state<MediaKeyKind>("playPause");

  function addAction() {
    if (newActionType === "launchApp") {
      if (!newPath) return;
      actions.push({ type: "launchApp", path: newPath });
      newPath = "";
    } else if (newActionType === "hotkey") {
      const keys = newKeys
        .split(",")
        .map((k) => k.trim())
        .filter((k) => k.length > 0);
      if (keys.length === 0) return;
      actions.push({ type: "hotkey", keys });
      newKeys = "";
    } else {
      actions.push({ type: "mediaKey", key: newMediaKey });
    }
  }

  function removeAction(index: number) {
    actions.splice(index, 1);
  }

  function moveAction(index: number, direction: -1 | 1) {
    const target = index + direction;
    if (target < 0 || target >= actions.length) return;
    [actions[index], actions[target]] = [actions[target], actions[index]];
  }

  function summarize(action: Action): string {
    switch (action.type) {
      case "launchApp":
        return `Launch: ${action.path}`;
      case "hotkey":
        return `Hotkey: ${action.keys.join(" + ")}`;
      case "mediaKey":
        return `Media: ${action.key}`;
    }
  }

  async function save() {
    await buttonStore.save({
      id: button?.id ?? crypto.randomUUID(),
      label: label || undefined,
      icon: icon || undefined,
      actions,
    });
    onClose();
  }

  async function remove() {
    if (button) {
      await buttonStore.remove(button.id);
    }
    onClose();
  }

  async function test() {
    if (!button) return;
    await invoke("press_button", { id: button.id });
  }
</script>

<div
  class="overlay"
  role="presentation"
  onclick={onClose}
  onkeydown={(e) => e.key === "Escape" && onClose()}
>
  <div
    class="panel"
    role="dialog"
    aria-modal="true"
    tabindex="-1"
    onclick={(e) => e.stopPropagation()}
  >
    <h2>{button ? "Edit Button" : "Add Button"}</h2>
    <label>
      Icon
      <input type="text" bind:value={icon} placeholder="🔘" maxlength="4" />
    </label>
    <label>
      Label
      <input type="text" bind:value={label} placeholder="Button label" />
    </label>

    <div class="action-list">
      <span class="section-label">Actions</span>
      {#each actions as action, index (index)}
        <div class="action-row">
          <span class="action-summary">{summarize(action)}</span>
          <button type="button" onclick={() => moveAction(index, -1)} disabled={index === 0}>↑</button>
          <button type="button" onclick={() => moveAction(index, 1)} disabled={index === actions.length - 1}>↓</button>
          <button type="button" class="danger" onclick={() => removeAction(index)}>×</button>
        </div>
      {/each}

      <div class="new-action">
        <select bind:value={newActionType}>
          <option value="launchApp">Launch App</option>
          <option value="hotkey">Hotkey</option>
          <option value="mediaKey">Media Key</option>
        </select>

        {#if newActionType === "launchApp"}
          <input type="text" bind:value={newPath} placeholder="/path/to/app" />
        {:else if newActionType === "hotkey"}
          <input type="text" bind:value={newKeys} placeholder="cmd, shift, s" />
        {:else}
          <select bind:value={newMediaKey}>
            <option value="playPause">Play/Pause</option>
            <option value="mute">Mute</option>
            <option value="nextTrack">Next Track</option>
            <option value="previousTrack">Previous Track</option>
          </select>
        {/if}
        <button type="button" onclick={addAction}>Add</button>
      </div>
    </div>

    <div class="footer-actions">
      {#if button}
        <button type="button" onclick={test}>Test</button>
        <button type="button" class="danger" onclick={remove}>Delete</button>
      {/if}
      <button type="button" onclick={onClose}>Cancel</button>
      <button type="button" onclick={save}>Save</button>
    </div>
  </div>
</div>

<style>
  .overlay {
    position: fixed;
    inset: 0;
    background: rgba(0, 0, 0, 0.4);
    display: flex;
    align-items: center;
    justify-content: center;
  }

  .panel {
    background: #ffffff;
    color: #0f0f0f;
    border-radius: 12px;
    padding: 20px;
    min-width: 320px;
    display: flex;
    flex-direction: column;
    gap: 12px;
  }

  label {
    display: flex;
    flex-direction: column;
    gap: 4px;
    font-size: 0.85rem;
    text-align: left;
  }

  input,
  select {
    border-radius: 8px;
    border: 1px solid rgba(0, 0, 0, 0.2);
    padding: 0.5em 0.75em;
    font-size: 1em;
  }

  .action-list {
    display: flex;
    flex-direction: column;
    gap: 6px;
    text-align: left;
  }

  .section-label {
    font-size: 0.75rem;
    text-transform: uppercase;
    opacity: 0.6;
  }

  .action-row {
    display: flex;
    align-items: center;
    gap: 6px;
  }

  .action-summary {
    flex: 1;
    font-size: 0.85rem;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .new-action {
    display: flex;
    gap: 6px;
    margin-top: 4px;
  }

  .new-action input,
  .new-action select {
    flex: 1;
  }

  .footer-actions {
    display: flex;
    justify-content: flex-end;
    gap: 8px;
    margin-top: 8px;
  }

  .danger {
    color: #c0392b;
  }

  .footer-actions .danger {
    margin-right: auto;
  }

  @media (prefers-color-scheme: dark) {
    .panel {
      background: #2f2f2f;
      color: #f6f6f6;
    }

    input,
    select {
      background: #0f0f0f98;
      border-color: rgba(255, 255, 255, 0.2);
      color: #f6f6f6;
    }
  }
</style>
