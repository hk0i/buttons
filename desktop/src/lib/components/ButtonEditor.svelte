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
    onSaved: () => void;
    onDeleted: () => void;
    onCancelled: () => void;
  } = $props();

  const id = button?.id ?? crypto.randomUUID();

  let label = $state(button?.label ?? "");
  let icon = $state(button?.icon ?? "");
  let actions = $state<Action[]>(button?.actions ? [...button.actions] : []);

  let hasAutosaved = $state(false);
  let saveTimeout: ReturnType<typeof setTimeout> | undefined;

  $effect(() => {
    // Reference every field so any edit re-arms the debounce below.
    label;
    icon;
    JSON.stringify(actions);

    // Don't autosave a blank new-button draft — avoids a phantom empty
    // tile showing up in the preview grid before the user types anything.
    if (!label.trim() && !icon.trim() && actions.length === 0) return;

    clearTimeout(saveTimeout);
    saveTimeout = setTimeout(persist, 500);

    return () => clearTimeout(saveTimeout);
  });

  async function persist() {
    hasAutosaved = true;
    await buttonStore.save({
      id,
      label: label || undefined,
      icon: icon || undefined,
      actions,
    });
  }

  let newActionType = $state<Action["type"]>("launchApp");
  let newPath = $state("");
  let newKeys = $state("");
  let newMediaKey = $state<MediaKeyKind>("playPause");
  let editingIndex = $state<number | null>(null);

  function resetActionForm() {
    editingIndex = null;
    newPath = "";
    newKeys = "";
  }

  function startEditAction(index: number) {
    const action = actions[index];
    editingIndex = index;
    newActionType = action.type;
    if (action.type === "launchApp") {
      newPath = action.path;
    } else if (action.type === "hotkey") {
      newKeys = action.keys.join(", ");
    } else {
      newMediaKey = action.key;
    }
  }

  function stopEditingAction() {
    resetActionForm();
  }

  // While editing, apply form changes to the action in place as the user
  // types — mirrors the whole-button autosave, no separate commit step.
  $effect(() => {
    if (editingIndex === null) return;
    const index = editingIndex;

    if (newActionType === "launchApp") {
      if (newPath) actions[index] = { type: "launchApp", path: newPath };
    } else if (newActionType === "hotkey") {
      const keys = newKeys
        .split(",")
        .map((k) => k.trim())
        .filter((k) => k.length > 0);
      if (keys.length > 0) actions[index] = { type: "hotkey", keys };
    } else {
      actions[index] = { type: "mediaKey", key: newMediaKey };
    }
  });

  function submitAction() {
    if (newActionType === "launchApp") {
      if (!newPath) return;
      actions.push({ type: "launchApp", path: newPath });
    } else if (newActionType === "hotkey") {
      const keys = newKeys
        .split(",")
        .map((k) => k.trim())
        .filter((k) => k.length > 0);
      if (keys.length === 0) return;
      actions.push({ type: "hotkey", keys });
    } else {
      actions.push({ type: "mediaKey", key: newMediaKey });
    }
    resetActionForm();
  }

  function removeAction(index: number) {
    actions.splice(index, 1);
    if (editingIndex === index) {
      resetActionForm();
    } else if (editingIndex !== null && index < editingIndex) {
      editingIndex -= 1;
    }
  }

  function moveAction(index: number, direction: -1 | 1) {
    const target = index + direction;
    if (target < 0 || target >= actions.length) return;
    [actions[index], actions[target]] = [actions[target], actions[index]];
    if (editingIndex === index) {
      editingIndex = target;
    } else if (editingIndex === target) {
      editingIndex = index;
    }
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

  async function finish() {
    clearTimeout(saveTimeout);
    await persist();
    onSaved();
  }

  async function remove() {
    clearTimeout(saveTimeout);
    if (button) {
      await buttonStore.remove(button.id);
    }
    onDeleted();
  }

  async function cancel() {
    clearTimeout(saveTimeout);
    if (button) {
      // Revert any autosaved edits back to the last-saved values.
      await buttonStore.save({ id, label: button.label, icon: button.icon, actions: button.actions });
    } else if (hasAutosaved) {
      // Discard the draft that autosave created.
      await buttonStore.remove(id);
    }
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

  <div class="appearance-group">
    <span class="section-label">Appearance</span>
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
  </div>

  <div class="action-list">
    <span class="section-label">Actions</span>
    {#each actions as action, index (index)}
      <div class="action-row" class:editing={editingIndex === index}>
        <span class="action-summary">{summarize(action)}</span>
        <button type="button" onclick={() => startEditAction(index)}>✎</button>
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
      {#if editingIndex === null}
        <button type="button" class="primary" onclick={submitAction}>Add</button>
      {:else}
        <button type="button" onclick={stopEditingAction} aria-label="Done editing action">✕</button>
      {/if}
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
    <button type="button" class="primary" onclick={finish}>Done</button>
  </div>
</div>

<style>
  .panel {
    flex: 1;
    min-height: 0;
    color: var(--key-white);
    display: flex;
    flex-direction: column;
    gap: 8px;
    font-family: var(--font-body);
    font-weight: 300;
  }

  h2 {
    font-family: var(--font-heading);
    font-weight: 700;
    font-size: 20px;
    margin: 0;
  }

  .appearance-group,
  .action-list,
  .footer-actions {
    background: var(--neutral-500);
    border-radius: 4px;
    padding: 16px;
  }

  .appearance-group {
    display: flex;
    flex-direction: column;
    gap: 12px;
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
    border-radius: 4px;
  }

  .action-row.editing {
    background: var(--neutral-400);
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
    user-select: text;
    -webkit-user-select: text;
    cursor: text;
  }

  .test-result.error {
    color: #ff8a75;
  }

  .footer-actions {
    display: flex;
    justify-content: flex-end;
    gap: 8px;
    margin-top: auto;
    padding-top: 8px;
  }

  .footer-actions .danger {
    margin-right: auto;
  }
</style>
