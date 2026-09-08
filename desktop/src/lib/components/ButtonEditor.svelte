<script lang="ts">
  import { invoke } from "@tauri-apps/api/core";
  import { open } from "@tauri-apps/plugin-dialog";
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
  let newKeys = $state<string[]>([]);
  let newMediaKey = $state<MediaKeyKind>("playPause");
  let editingIndex = $state<number | null>(null);
  let isRecordingHotkey = $state(false);

  const modifierKeyNames = new Set(["Meta", "Control", "Alt", "Shift"]);

  // Maps a KeyboardEvent.key to the token vocabulary parse_key (actions.rs)
  // already understands, so a recorded combo round-trips the same as one
  // typed by hand.
  const KEY_TOKENS: Record<string, string> = {
    Meta: "cmd",
    Control: "ctrl",
    Alt: "alt",
    Shift: "shift",
    " ": "space",
    ArrowUp: "up",
    ArrowDown: "down",
    ArrowLeft: "left",
    ArrowRight: "right",
  };

  function keyToToken(key: string): string {
    return KEY_TOKENS[key] ?? key.toLowerCase();
  }

  // Captures a live key combo instead of requiring it typed by hand.
  // Modifier-only keydowns update the in-progress preview; the first
  // non-modifier key finalizes the combo and stops recording. Escape alone
  // cancels rather than being recorded, matching how most hotkey recorders
  // behave.
  $effect(() => {
    if (newActionType !== "hotkey") isRecordingHotkey = false;
  });

  $effect(() => {
    if (!isRecordingHotkey) return;

    function handleKeydown(event: KeyboardEvent) {
      event.preventDefault();
      if (event.repeat) return;

      const modifiers: string[] = [];
      if (event.metaKey) modifiers.push("cmd");
      if (event.ctrlKey) modifiers.push("ctrl");
      if (event.altKey) modifiers.push("alt");
      if (event.shiftKey) modifiers.push("shift");

      if (event.key === "Escape" && modifiers.length === 0) {
        isRecordingHotkey = false;
        return;
      }

      if (modifierKeyNames.has(event.key)) {
        newKeys = modifiers;
        return;
      }

      newKeys = [...modifiers, keyToToken(event.key)];
      isRecordingHotkey = false;
    }

    window.addEventListener("keydown", handleKeydown, true);
    return () => window.removeEventListener("keydown", handleKeydown, true);
  });

  function removeKeyToken(index: number) {
    newKeys = newKeys.filter((_, i) => i !== index);
  }

  async function pickAppPath() {
    // directory: false is deliberate — on macOS, NSOpenPanel still lets you
    // pick a .app bundle this way since it treats bundles as packages, not
    // browsable folders.
    const path = await open({ directory: false, multiple: false });
    if (path) newPath = path;
  }

  function resetActionForm() {
    editingIndex = null;
    newPath = "";
    newKeys = [];
    isRecordingHotkey = false;
  }

  function startEditAction(index: number) {
    const action = actions[index];
    editingIndex = index;
    newActionType = action.type;
    if (action.type === "launchApp") {
      newPath = action.path;
    } else if (action.type === "hotkey") {
      newKeys = [...action.keys];
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
      if (newKeys.length > 0) actions[index] = { type: "hotkey", keys: newKeys };
    } else {
      actions[index] = { type: "mediaKey", key: newMediaKey };
    }
  });

  function submitAction() {
    if (newActionType === "launchApp") {
      if (!newPath) return;
      actions.push({ type: "launchApp", path: newPath });
    } else if (newActionType === "hotkey") {
      if (newKeys.length === 0) return;
      actions.push({ type: "hotkey", keys: newKeys });
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
        <button type="button" onclick={pickAppPath}>Browse…</button>
      {:else if newActionType === "hotkey"}
        <div class="hotkey-chips" class:recording={isRecordingHotkey}>
          {#each newKeys as key, index (index)}
            {#if index > 0}<span class="key-plus">+</span>{/if}
            <span class="key-chip">
              {key}
              {#if !isRecordingHotkey}
                <button
                  type="button"
                  class="chip-remove"
                  onclick={() => removeKeyToken(index)}
                  aria-label="Remove {key}"
                >
                  ×
                </button>
              {/if}
            </span>
          {:else}
            <span class="hotkey-placeholder">
              {isRecordingHotkey ? "Press keys…" : "No keys set"}
            </span>
          {/each}
        </div>
        <button type="button" onclick={() => (isRecordingHotkey = !isRecordingHotkey)}>
          {isRecordingHotkey ? "Stop" : "Record"}
        </button>
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

  .hotkey-chips {
    flex: 1;
    display: flex;
    align-items: center;
    flex-wrap: wrap;
    gap: 6px;
    background: var(--neutral-400);
    border: 1px solid var(--neutral-600);
    border-radius: 4px;
    padding: 6px 10px;
    min-height: 32px;
    box-sizing: border-box;
  }

  .hotkey-chips.recording {
    border-color: var(--primary-700);
  }

  .key-chip {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    background: var(--neutral-600);
    border: 1px solid var(--neutral-700);
    border-radius: 4px;
    padding: 2px 6px;
    font-size: 13px;
    line-height: 1.4;
  }

  .key-plus {
    opacity: 0.6;
    font-size: 13px;
  }

  .chip-remove {
    all: unset;
    cursor: pointer;
    opacity: 0.6;
    font-size: 13px;
    line-height: 1;
  }

  .chip-remove:hover {
    opacity: 1;
  }

  .hotkey-placeholder {
    opacity: 0.5;
    font-size: 13px;
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
  }

  .footer-actions .danger {
    margin-right: auto;
  }
</style>
