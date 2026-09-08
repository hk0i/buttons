<script lang="ts">
  let {
    keys = $bindable<string[]>([]),
    recording = $bindable(false),
  }: { keys?: string[]; recording?: boolean } = $props();

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
    if (!recording) return;

    function handleKeydown(event: KeyboardEvent) {
      event.preventDefault();
      if (event.repeat) return;

      const modifiers: string[] = [];
      if (event.metaKey) modifiers.push("cmd");
      if (event.ctrlKey) modifiers.push("ctrl");
      if (event.altKey) modifiers.push("alt");
      if (event.shiftKey) modifiers.push("shift");

      if (event.key === "Escape" && modifiers.length === 0) {
        recording = false;
        return;
      }

      if (modifierKeyNames.has(event.key)) {
        keys = modifiers;
        return;
      }

      keys = [...modifiers, keyToToken(event.key)];
      recording = false;
    }

    window.addEventListener("keydown", handleKeydown, true);
    return () => window.removeEventListener("keydown", handleKeydown, true);
  });

  function removeKeyToken(index: number) {
    keys = keys.filter((_, i) => i !== index);
  }
</script>

<div class="hotkey-chips" class:recording>
  {#each keys as key, index (index)}
    {#if index > 0}<span class="key-plus">+</span>{/if}
    <span class="key-chip">
      {key}
      {#if !recording}
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
      {recording ? "Press keys…" : "No keys set"}
    </span>
  {/each}
</div>
<button type="button" onclick={() => (recording = !recording)}>
  {recording ? "Stop" : "Record"}
</button>

<style>
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
</style>
