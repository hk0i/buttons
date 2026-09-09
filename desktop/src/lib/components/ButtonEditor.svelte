<script lang="ts">
  import { invoke } from "@tauri-apps/api/core";
  import type { Action, Button as ButtonModel, MediaKeyKind } from "$lib/types/button";
  import { buttonStore } from "$lib/stores/buttons.svelte";
  import DeckButton from "./DeckButton.svelte";
  import LaunchAppField from "./LaunchAppField.svelte";
  import HotkeyField from "./HotkeyField.svelte";
  import MediaKeyField from "./MediaKeyField.svelte";

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

  // Guards against a stray keydown listener: HotkeyField unmounts (and cleans
  // itself up) when the dropdown moves off "hotkey", but the bound recording
  // flag would otherwise stay stuck true and silently resume capturing keys
  // if the user switches back to "hotkey" later.
  $effect(() => {
    if (newActionType !== "hotkey") isRecordingHotkey = false;
  });

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

  let justAddedIndex = $state<number | null>(null);
  let justAddedTimeout: ReturnType<typeof setTimeout> | undefined;

  function flashJustAdded(index: number) {
    justAddedIndex = index;
    clearTimeout(justAddedTimeout);
    justAddedTimeout = setTimeout(() => (justAddedIndex = null), 1000);
  }

  // Option (b) from the UX discussion, chosen after (a) — auto-commit on
  // valid — proved to have a structural problem: Media Key has no empty
  // state, so its validity can't tell "user just switched the dropdown" from
  // "user chose a value," and it either committed prematurely or (before that
  // was caught) looped forever re-adding itself. Explicit Add avoids needing
  // that distinction at all; hasPendingDraft below covers the original
  // complaint (easy to forget to click Add) with a visible cue instead.
  let hasPendingDraft = $derived(
    editingIndex === null &&
      (newActionType === "launchApp"
        ? newPath.length > 0
        : newActionType === "hotkey"
          ? newKeys.length > 0
          : true),
  );

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
    flashJustAdded(actions.length - 1);
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
    if (hasPendingDraft && !confirm("You have an unsaved action that hasn't been added yet. Finish anyway and discard it?")) {
      return;
    }
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
    if (hasPendingDraft && !confirm("You have an unsaved action that hasn't been added yet. Cancel anyway and discard it?")) {
      return;
    }
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
      <div class="action-row" class:editing={editingIndex === index} class:just-added={justAddedIndex === index}>
        <span class="action-summary">{summarize(action)}</span>
        <button type="button" onclick={() => startEditAction(index)}>✎</button>
        <button type="button" onclick={() => moveAction(index, -1)} disabled={index === 0}>↑</button>
        <button type="button" onclick={() => moveAction(index, 1)} disabled={index === actions.length - 1}>↓</button>
        <button type="button" class="danger" onclick={() => removeAction(index)}>×</button>
      </div>
    {/each}

    <div class="new-action" class:has-draft={hasPendingDraft}>
      <select bind:value={newActionType}>
        <option value="launchApp">Launch App</option>
        <option value="hotkey">Hotkey</option>
        <option value="mediaKey">Media Key</option>
      </select>

      {#if newActionType === "launchApp"}
        <LaunchAppField bind:path={newPath} />
      {:else if newActionType === "hotkey"}
        <HotkeyField bind:keys={newKeys} bind:recording={isRecordingHotkey} />
      {:else}
        <MediaKeyField bind:key={newMediaKey} />
      {/if}
      {#if editingIndex === null}
        <button type="button" class="primary" onclick={submitAction}>Add</button>
      {:else}
        <button type="button" onclick={stopEditingAction} aria-label="Done editing action">✕</button>
      {/if}
    </div>
    {#if hasPendingDraft}
      <p class="draft-hint">Unsaved — click Add to include this action.</p>
    {/if}
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
    background: transparent;
    transition: background 1s ease;
  }

  .action-row.editing {
    background: var(--neutral-400);
  }

  .action-row.just-added {
    background: var(--primary-700);
    transition: none;
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
    border: 1px solid transparent;
    border-radius: 4px;
    padding: 2px;
  }

  .new-action.has-draft {
    border-color: var(--primary-700);
  }

  .new-action select {
    flex: 1;
    padding: 6px 10px;
  }

  .draft-hint {
    margin: 4px 0 0;
    font-size: 12px;
    color: var(--primary-700);
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
