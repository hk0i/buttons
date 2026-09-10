<script lang="ts">
  import { invoke } from "@tauri-apps/api/core";
  import type { Action, Button as ButtonModel, ButtonContent, MediaKeyKind } from "$lib/types/button";
  import { configStore } from "$lib/stores/config.svelte";
  // Shadows window.confirm(), which silently returns true in Tauri's WKWebView.
  import { confirm } from "$lib/stores/confirm.svelte";
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

  // Snapshot of where this button lives, captured once at open time — saves
  // always target this fixed location, not wherever navigation has since
  // moved on to (see config store's saveButtonAt).
  const homePageId = configStore.currentPageId;
  const homeFolderPath = [...configStore.folderStack];

  let label = $state(button?.label ?? "");
  let icon = $state(button?.icon ?? "");
  let actions = $state<Action[]>(
    button?.content.type === "actions" ? [...button.content.actions] : [],
  );

  // A folder button's own nested grid. Kept around even while `isFolder` is
  // off so toggling folder-ness on and off within one editing session (or
  // just editing label/icon on an existing folder) never clobbers whatever
  // nested buttons already live inside it.
  let isFolder = $state(button?.content.type === "folder");
  let folderButtons = $state<ButtonModel[]>(
    button?.content.type === "folder" ? [...button.content.buttons] : newFolderButtons(),
  );

  function newFolderButtons(): ButtonModel[] {
    return [{ id: crypto.randomUUID(), content: { type: "back" } }];
  }

  let hasAutosaved = $state(false);
  let saveTimeout: ReturnType<typeof setTimeout> | undefined;

  $effect(() => {
    // Reference every field so any edit re-arms the debounce below.
    label;
    icon;
    isFolder;
    JSON.stringify(actions);

    // Don't autosave a blank new-button draft — avoids a phantom empty
    // tile showing up in the preview grid before the user types anything.
    if (!label.trim() && !icon.trim() && actions.length === 0 && !isFolder) return;

    clearTimeout(saveTimeout);
    saveTimeout = setTimeout(persist, 500);

    return () => clearTimeout(saveTimeout);
  });

  async function persist() {
    hasAutosaved = true;
    const content: ButtonContent = isFolder
      ? { type: "folder", buttons: folderButtons }
      : { type: "actions", actions };
    await configStore.saveButtonAt(homePageId, homeFolderPath, {
      id,
      label: label || undefined,
      icon: icon || undefined,
      content,
    });
  }

  // Navigates into this folder's own grid — same dispatch a double-click in
  // the preview grid triggers. Flushes any pending autosave first so the
  // folder-toggle change is on disk before its contents come into view, then
  // closes the editor — leaving it open would keep editing a button that's
  // no longer even in view.
  async function showContent() {
    clearTimeout(saveTimeout);
    await persist();
    configStore.enterFolder({ id, label, icon, content: { type: "folder", buttons: folderButtons } });
    onSaved();
  }

  function goBack() {
    configStore.exitFolder();
    onCancelled();
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
    if (
      hasPendingDraft &&
      !(await confirm({
        title: "Discard unsaved action?",
        body: "You have an action that hasn't been added yet. Finish anyway and discard it?",
        confirmLabel: "Discard & finish",
        destructive: true,
      }))
    ) {
      return;
    }
    clearTimeout(saveTimeout);
    await persist();
    onSaved();
  }

  async function remove() {
    const name = button?.label?.trim();
    const ok = await confirm({
      title: "Delete button?",
      body: name
        ? `"${name}" will be removed. This can't be undone.`
        : "This button will be removed. This can't be undone.",
      confirmLabel: "Delete",
      destructive: true,
    });
    if (!ok) return;
    clearTimeout(saveTimeout);
    if (button) {
      await configStore.removeButtonAt(homePageId, homeFolderPath, button.id);
    }
    onDeleted();
  }

  async function cancel() {
    if (
      hasPendingDraft &&
      !(await confirm({
        title: "Discard unsaved action?",
        body: "You have an action that hasn't been added yet. Cancel anyway and discard it?",
        confirmLabel: "Discard & close",
        destructive: true,
      }))
    ) {
      return;
    }
    clearTimeout(saveTimeout);
    if (button) {
      // Revert any autosaved edits back to the last-saved values.
      await configStore.saveButtonAt(homePageId, homeFolderPath, { id, label: button.label, icon: button.icon, content: button.content });
    } else if (hasAutosaved) {
      // Discard the draft that autosave created.
      await configStore.removeButtonAt(homePageId, homeFolderPath, id);
    }
    onCancelled();
  }

  let testResult = $state<{ ok: boolean; message: string } | null>(null);

  async function test() {
    testResult = null;
    try {
      await invoke("run_actions", { actions });
      testResult = { ok: true, message: "All actions ran successfully." };
    } catch (e) {
      testResult = { ok: false, message: String(e) };
    }
  }
</script>

{#if button?.content.type === "back"}
  <div class="panel">
    <h2>Back</h2>
    <div class="action-list">
      <span class="section-label">Navigation</span>
      <button type="button" class="primary" onclick={goBack}>Go Back</button>
    </div>
    <div class="footer-actions">
      <button type="button" onclick={onCancelled}>Close</button>
    </div>
  </div>
{:else}
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
      <label class="folder-toggle">
        <input type="checkbox" bind:checked={isFolder} />
        Is folder
      </label>
    </div>

    {#if isFolder}
      <div class="action-list">
        <span class="section-label">Content</span>
        <button type="button" class="primary" onclick={showContent}>Show Content</button>
      </div>
    {:else}
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
    {/if}

    {#if testResult}
      <p class="test-result" class:error={!testResult.ok}>{testResult.message}</p>
    {/if}

    <div class="footer-actions">
      {#if button && !isFolder}
        <button type="button" class="primary" onclick={test}>Test</button>
      {/if}
      {#if button}
        <button type="button" class="danger" onclick={remove}>Delete</button>
      {/if}
      <button type="button" onclick={cancel}>Cancel</button>
      <button type="button" class="primary" onclick={finish}>Done</button>
    </div>
  </div>
{/if}

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

  .folder-toggle {
    display: flex;
    align-items: center;
    gap: 6px;
    font-size: 14px;
    cursor: pointer;
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
