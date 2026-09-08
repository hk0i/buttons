<script lang="ts">
  import { invoke } from "@tauri-apps/api/core";
  import type { Action, Button as ButtonModel, MediaKeyKind } from "$lib/types/button";
  import { buttonStore } from "$lib/stores/buttons.svelte";
  import DeckButton from "./DeckButton.svelte";

  let {
    button,
    onSaved,
    onDeleted,
    onCancelled,
  }: {
    button: ButtonModel | null;
    onSaved: (id: string) => void;
    onDeleted: () => void;
    onCancelled: () => void;
  } = $props();

  let label = $state(button?.label ?? "");
  let icon = $state(button?.icon ?? "");
  let actions = $state<Action[]>(button?.actions ? [...button.actions] : []);

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
    const id = button?.id ?? crypto.randomUUID();
    await buttonStore.save({
      id,
      label: label || undefined,
      icon: icon || undefined,
      actions,
    });
    onSaved(id);
  }

  async function remove() {
    if (button) {
      await buttonStore.remove(button.id);
    }
    onDeleted();
  }

  function cancel() {
    onCancelled();
  }

  let testResult = $state<{ ok: boolean; message: string } | null>(null);

  async function test() {
    if (!button) return;
    testResult = null;
    try {
      await invoke("press_button", { id: button.id });
      testResult = { ok: true, message: "All actions ran successfully." };
    } catch (e) {
      testResult = { ok: false, message: String(e) };
    }
  }
</script>

<div class="panel">
  <h2>{button ? "Edit Button" : "Add Button"}</h2>

  <div class="identity-row">
    <div class="icon-preview">
      <DeckButton {icon} {label} />
    </div>
    <label class="label-field">
      Button Label:
      <input type="text" bind:value={label} placeholder="None" />
    </label>
    <label class="icon-field">
      Icon:
      <input type="text" bind:value={icon} placeholder="🔘" maxlength="4" />
    </label>
  </div>

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
      <button type="button" class="primary" onclick={addAction}>Add</button>
    </div>
  </div>

  {#if testResult}
    <p class="test-result" class:error={!testResult.ok}>{testResult.message}</p>
  {/if}

  <div class="footer-actions">
    {#if button}
      <button type="button" class="primary" onclick={test}>Test</button>
      <button type="button" class="danger" onclick={remove}>Delete</button>
    {/if}
    <button type="button" onclick={cancel}>Cancel</button>
    <button type="button" class="primary" onclick={save}>Save</button>
  </div>
</div>

<style>
  .panel {
    background: var(--neutral-500);
    color: var(--key-white);
    border-radius: 4px;
    padding: 16px;
    display: flex;
    flex-direction: column;
    gap: 16px;
    font-family: var(--font-body);
    font-weight: 300;
  }

  h2 {
    font-family: var(--font-heading);
    font-weight: 700;
    font-size: 20px;
    margin: 0;
  }

  .identity-row {
    display: flex;
    align-items: flex-end;
    gap: 16px;
  }

  .icon-preview {
    width: 72px;
    height: 72px;
    flex-shrink: 0;
  }

  .label-field,
  .icon-field {
    display: flex;
    flex-direction: column;
    gap: 4px;
    font-size: 16px;
  }

  .label-field {
    flex: 1;
  }

  .icon-field {
    width: 96px;
  }

  input,
  select {
    background: var(--neutral-400);
    border: 1px solid var(--neutral-600);
    color: var(--key-white);
    border-radius: 4px;
    padding: 10px 16px;
    font-family: var(--font-body);
    font-weight: 300;
    font-size: 16px;
  }

  .action-list {
    display: flex;
    flex-direction: column;
    gap: 6px;
  }

  .section-label {
    font-size: 12px;
    text-transform: uppercase;
    opacity: 0.7;
  }

  .action-row {
    display: flex;
    align-items: center;
    gap: 6px;
  }

  .action-summary {
    flex: 1;
    font-size: 14px;
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
    padding: 6px 10px;
  }

  button {
    background: var(--neutral-600);
    border: 1px solid var(--neutral-700);
    color: var(--key-white);
    border-radius: 4px;
    padding: 4px 16px;
    height: 32px;
    font-family: var(--font-body);
    font-weight: 500;
    font-size: 12px;
    cursor: pointer;
  }

  button.primary {
    background: var(--primary-700);
    border-color: var(--primary-900);
    box-shadow: 2px 2px 2px var(--primary-900);
  }

  button.danger {
    background: transparent;
    border-color: #c0392b;
    color: #ff8a75;
  }

  button:disabled {
    opacity: 0.4;
    cursor: default;
  }

  .test-result {
    font-size: 13px;
    margin: 0;
    color: #7ee787;
  }

  .test-result.error {
    color: #ff8a75;
  }

  .footer-actions {
    display: flex;
    justify-content: flex-end;
    gap: 8px;
  }

  .footer-actions .danger {
    margin-right: auto;
  }
</style>
