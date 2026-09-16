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

  // The 3-way content-type choice a boolean can't express once Switch joins
  // Actions/Folder. Every branch's own data (plainActions, folderButtons,
  // the switchOff/On fields below) is kept around even while a different
  // type is selected — same "preserve while not selected" treatment
  // folderButtons already used, extended to a Switch's two states — so
  // toggling the dropdown back and forth within one editing session never
  // clobbers whatever that branch already held.
  let contentType = $state<"actions" | "folder" | "switch">(
    button?.content.type === "folder"
      ? "folder"
      : button?.content.type === "switch"
        ? "switch"
        : "actions",
  );

  let plainActions = $state<Action[]>(
    button?.content.type === "actions" ? [...button.content.actions] : [],
  );

  let folderButtons = $state<ButtonModel[]>(
    button?.content.type === "folder" ? [...button.content.buttons] : newFolderButtons(),
  );

  function newFolderButtons(): ButtonModel[] {
    return [{ id: crypto.randomUUID(), content: { type: "back" } }];
  }

  // Two-state toggle content — off/on named to match config.rs's
  // ButtonContent::Switch exactly. Each state gets its own label/icon/
  // actions, split into separate $state primitives (not one SwitchState
  // object) so plain <input bind:value> works the same way the top-level
  // label/icon fields above already do.
  let activeTab = $state<"off" | "on">("off");
  let switchOffLabel = $state(button?.content.type === "switch" ? (button.content.off.label ?? "") : "");
  let switchOffIcon = $state(button?.content.type === "switch" ? (button.content.off.icon ?? "") : "");
  let switchOffActions = $state<Action[]>(
    button?.content.type === "switch" ? [...button.content.off.actions] : [],
  );
  let switchOnLabel = $state(button?.content.type === "switch" ? (button.content.on.label ?? "") : "");
  let switchOnIcon = $state(button?.content.type === "switch" ? (button.content.on.icon ?? "") : "");
  let switchOnActions = $state<Action[]>(
    button?.content.type === "switch" ? [...button.content.on.actions] : [],
  );

  // The action-list sub-form below (add/edit/remove/move) is one copy,
  // reused for both a plain Actions button and whichever Switch tab is
  // active — not duplicated three times. `currentActions` is a live
  // reference to whichever underlying $state array applies, not a copy:
  // mutating it (push/splice/index-assign) mutates that array in place,
  // same as if the sub-form's functions still closed over `actions`
  // directly.
  let currentActions = $derived(
    contentType === "switch" ? (activeTab === "off" ? switchOffActions : switchOnActions) : plainActions,
  );

  // Switching content type or tab mid-draft would otherwise leave
  // editingIndex pointing at an index in a now-different array.
  $effect(() => {
    contentType;
    activeTab;
    resetActionForm();
  });

  let hasAutosaved = $state(false);
  let saveTimeout: ReturnType<typeof setTimeout> | undefined;

  $effect(() => {
    // Reference every field so any edit re-arms the debounce below.
    label;
    icon;
    contentType;
    JSON.stringify(plainActions);
    switchOffLabel;
    switchOffIcon;
    JSON.stringify(switchOffActions);
    switchOnLabel;
    switchOnIcon;
    JSON.stringify(switchOnActions);

    // Don't autosave a blank new-button draft — avoids a phantom empty
    // tile showing up in the preview grid before the user types anything.
    // Choosing Folder or Switch is itself meaningful, same as the old
    // isFolder boolean was — only bare Actions with nothing in it stays
    // unsaved.
    if (!label.trim() && !icon.trim() && contentType === "actions" && plainActions.length === 0) {
      return;
    }

    clearTimeout(saveTimeout);
    saveTimeout = setTimeout(persist, 500);

    return () => clearTimeout(saveTimeout);
  });

  async function persist() {
    hasAutosaved = true;
    const content: ButtonContent =
      contentType === "folder"
        ? { type: "folder", buttons: folderButtons }
        : contentType === "switch"
          ? {
              type: "switch",
              off: {
                label: switchOffLabel || undefined,
                icon: switchOffIcon || undefined,
                actions: switchOffActions,
              },
              on: {
                label: switchOnLabel || undefined,
                icon: switchOnIcon || undefined,
                actions: switchOnActions,
              },
            }
          : { type: "actions", actions: plainActions };
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
    const action = currentActions[index];
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
      if (newPath) currentActions[index] = { type: "launchApp", path: newPath };
    } else if (newActionType === "hotkey") {
      if (newKeys.length > 0) currentActions[index] = { type: "hotkey", keys: newKeys };
    } else {
      currentActions[index] = { type: "mediaKey", key: newMediaKey };
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
      currentActions.push({ type: "launchApp", path: newPath });
    } else if (newActionType === "hotkey") {
      if (newKeys.length === 0) return;
      currentActions.push({ type: "hotkey", keys: newKeys });
    } else {
      currentActions.push({ type: "mediaKey", key: newMediaKey });
    }
    flashJustAdded(currentActions.length - 1);
    resetActionForm();
  }

  function removeAction(index: number) {
    currentActions.splice(index, 1);
    if (editingIndex === index) {
      resetActionForm();
    } else if (editingIndex !== null && index < editingIndex) {
      editingIndex -= 1;
    }
  }

  function moveAction(index: number, direction: -1 | 1) {
    const target = index + direction;
    if (target < 0 || target >= currentActions.length) return;
    [currentActions[index], currentActions[target]] = [currentActions[target], currentActions[index]];
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

  // Both Done and Cancel walk away from an in-progress action that was never
  // added to the list. Returns true when it's safe to proceed — no draft, or
  // the user chose to lose it.
  async function okToDiscardDraft(confirmLabel: string): Promise<boolean> {
    if (!hasPendingDraft) return true;
    return confirm({
      title: "Discard unsaved action?",
      body: "You have an action that hasn't been added yet. Discard it?",
      confirmLabel,
      destructive: true,
    });
  }

  async function finish() {
    if (!(await okToDiscardDraft("Discard & finish"))) return;
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
    if (!(await okToDiscardDraft("Discard & close"))) return;
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

  // Simulates a full real press through the same shared backend path a
  // real ButtonPress uses (server.rs's execute_press) — for a Switch this
  // runs the current state's actions and flips on success, not a separate
  // testing-only code path that could drift from what a real press does.
  // Flushes the pending autosave first so test_button (which loads
  // buttons.json fresh) sees this session's latest edits, not a stale
  // on-disk copy — same flush finish()/showContent() already do before
  // navigating away.
  async function test() {
    testResult = null;
    try {
      clearTimeout(saveTimeout);
      await persist();
      await invoke("test_button", { buttonId: id });
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
      {#if contentType !== "switch"}
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
      {/if}
      <label class="content-type-field">
        Content:
        <select bind:value={contentType}>
          <option value="actions">Actions</option>
          <option value="folder">Folder</option>
          <option value="switch">Switch</option>
        </select>
      </label>
    </div>

    {#if contentType === "folder"}
      <div class="action-list">
        <span class="section-label">Content</span>
        <button type="button" class="primary" onclick={showContent}>Show Content</button>
      </div>
    {:else}
      {#if contentType === "switch"}
        <div class="switch-tabs">
          <button type="button" class:active={activeTab === "off"} onclick={() => (activeTab = "off")}>
            Off
          </button>
          <button type="button" class:active={activeTab === "on"} onclick={() => (activeTab = "on")}>
            On
          </button>
        </div>
        <div class="appearance-group">
          <span class="section-label">{activeTab === "off" ? "Off" : "On"} Appearance</span>
          {#if activeTab === "off"}
            <div class="identity-row">
              <div class="icon-preview">
                <DeckButton icon={switchOffIcon} label={switchOffLabel} />
              </div>
              <label class="label-field">
                Label:
                <input type="text" bind:value={switchOffLabel} placeholder="None" />
              </label>
              <label class="icon-field">
                Icon:
                <input type="text" bind:value={switchOffIcon} placeholder="🔘" maxlength="4" />
              </label>
            </div>
          {:else}
            <div class="identity-row">
              <div class="icon-preview">
                <DeckButton icon={switchOnIcon} label={switchOnLabel} />
              </div>
              <label class="label-field">
                Label:
                <input type="text" bind:value={switchOnLabel} placeholder="None" />
              </label>
              <label class="icon-field">
                Icon:
                <input type="text" bind:value={switchOnIcon} placeholder="🔘" maxlength="4" />
              </label>
            </div>
          {/if}
        </div>
      {/if}

      <div class="action-list">
        <span class="section-label">
          {contentType === "switch" ? `${activeTab === "off" ? "Off" : "On"} Actions` : "Actions"}
        </span>
        {#each currentActions as action, index (index)}
          <div class="action-row" class:editing={editingIndex === index} class:just-added={justAddedIndex === index}>
            <span class="action-summary">{summarize(action)}</span>
            <button type="button" onclick={() => startEditAction(index)}>✎</button>
            <button type="button" onclick={() => moveAction(index, -1)} disabled={index === 0}>↑</button>
            <button type="button" onclick={() => moveAction(index, 1)} disabled={index === currentActions.length - 1}>↓</button>
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
            <HotkeyField bind:keys={newKeys} bind:isRecording={isRecordingHotkey} />
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
      {#if button && contentType !== "folder"}
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

  .content-type-field {
    display: flex;
    align-items: center;
    gap: 8px;
    font-size: 14px;
  }

  .switch-tabs {
    display: flex;
    gap: 4px;
  }

  .switch-tabs button {
    flex: 1;
    padding: 8px;
    border-radius: 4px;
    background: var(--neutral-500);
    opacity: 0.6;
  }

  .switch-tabs button.active {
    background: var(--primary-700);
    opacity: 1;
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
