<script lang="ts">
  import "$lib/styles/tokens.css";
  import { onMount } from "svelte";
  import { resolve } from "$app/paths";
  import { configStore } from "$lib/stores/config.svelte";
  import { switchStatesStore } from "$lib/stores/switchStates.svelte";
  import ButtonEditor from "$lib/components/ButtonEditor.svelte";
  import PreviewPane from "$lib/components/PreviewPane.svelte";
  import ProfileSwitcher from "$lib/components/ProfileSwitcher.svelte";
  import type { Button as ButtonModel } from "$lib/types/button";

  let selected = $state<ButtonModel | "new" | undefined>(undefined);
  let orientation = $state<"portrait" | "landscape">("portrait");

  onMount(async () => {
    await configStore.load();
    // Not part of Config/ConfigStore — desktop's own runtime record of which
    // state each Switch button is currently showing (switch_state.json),
    // loaded independently. See slice 09 spec, § Files to Touch #9.
    await switchStatesStore.load();
  });

  function startAdd() {
    selected = "new";
  }

  function selectById(id: string | undefined) {
    selected = configStore.visibleButtons.find((b) => b.id === id) ?? configStore.visibleButtons[0] ?? undefined;
  }

  function onSaved() {
    selected = undefined;
  }

  function onDeleted() {
    selectById(undefined);
  }

  function onCancelled() {
    selected = undefined;
  }
</script>

<div class="app">
  <header class="app-header">
    <h1>Buttons</h1>
    <div class="header-actions">
      <div class="header-profile">
        <ProfileSwitcher />
      </div>
      <!-- Behind a click, not shown by default anywhere else — the QR is
           only generated while this view is deliberately open, which is
           what lets its token stay short-lived. See Scope -> In item 7. -->
      <a class="pair-device-link" href={resolve("/pairing")}>Pair device…</a>
    </div>
  </header>

  <div class="app-body" class:landscape={orientation === "landscape"}>
    <div class="preview-wrapper">
      <PreviewPane
        selectedId={selected && selected !== "new" ? selected.id : undefined}
        onSelect={(b) => (selected = b)}
        onAdd={startAdd}
        onNavigate={() => (selected = undefined)}
        bind:orientation
      />
    </div>

    <div class="editor-pane" class:active={selected !== undefined}>
      <div class="editor-scroll">
        {#if selected === "new"}
          {#key "new"}
            <ButtonEditor button={null} {onSaved} {onDeleted} {onCancelled} />
          {/key}
        {:else if selected}
          {#key selected.id}
            <ButtonEditor button={selected} {onSaved} {onDeleted} {onCancelled} />
          {/key}
        {:else}
          <p class="empty-state">Select a button in the preview to edit it, or click + Add to create one.</p>
        {/if}
      </div>
    </div>
  </div>
</div>

<style>
  :global(body) {
    margin: 0;
    background: var(--neutral-600);
    color: var(--key-white);
    font-family: var(--font-body);
    user-select: none;
    -webkit-user-select: none;
    cursor: default;
  }

  :global(input),
  :global(textarea) {
    user-select: text;
    -webkit-user-select: text;
    cursor: text;
  }

  .app {
    display: flex;
    flex-direction: column;
    height: 100vh;
    /* No page-level scroll — this should read as a native app shell, not a
       web page. Every pane below manages its own overflow internally
       (.phone scrolls its simulated device screen, .editor-pane scrolls its
       own form) rather than letting the whole window grow past its bounds. */
    overflow: hidden;
  }

  .app-header {
    background: var(--neutral-700);
    padding: 10px 16px;
    flex-shrink: 0;
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 16px;
  }

  .app-header h1 {
    font-family: var(--font-heading);
    font-weight: 700;
    font-size: 24px;
    margin: 0;
    color: var(--key-white);
  }

  /* Groups the profile switcher and the pairing entry point on the header's
     trailing edge, so adding the pairing link doesn't push ProfileSwitcher
     toward the center under justify-content: space-between. */
  .header-actions {
    display: flex;
    align-items: center;
    gap: 16px;
    min-width: 0;
  }

  /* Cap the switcher's width so it sits as a control beside the title rather
     than stretching the whole window (its two <select>s are flex:1
     internally, sharing this width). min-width:0 lets it shrink below
     content width at narrow windows so the header never overflows. */
  .header-profile {
    flex: 0 1 440px;
    min-width: 0;
  }

  /* ProfileSwitcher's controls carry a --neutral-700 border — the exact
     colour of this header's background, so it would vanish. Lift it to a
     visible edge only where the switcher sits here; the component's own
     styles (tuned for the darker preview pane) stay untouched. */
  .header-profile :global(select),
  .header-profile :global(input),
  .header-profile :global(button) {
    border-color: var(--neutral-500);
  }

  .pair-device-link {
    flex-shrink: 0;
    color: var(--key-white);
    font-size: 14px;
    text-decoration: none;
    border: 1px solid var(--neutral-500);
    border-radius: 4px;
    padding: 4px 12px;
    height: 32px;
    box-sizing: border-box;
    display: inline-flex;
    align-items: center;
  }

  .pair-device-link:hover {
    background: var(--neutral-500);
  }

  .app-body {
    display: flex;
    flex-direction: row;
    flex: 1;
    min-height: 0;
  }

  .app-body.landscape {
    flex-direction: column;
  }

  .editor-pane {
    flex: 1;
    padding: 16px;
    display: flex;
    flex-direction: column;
    gap: 16px;
    overflow-y: auto;
  }

  .preview-wrapper {
    flex: 0 0 380px;
    min-width: 340px;
  }

  .app-body.landscape .preview-wrapper {
    flex: 0 0 auto;
    width: 100%;
    min-width: 0;
  }

  .editor-scroll {
    flex: 1;
    display: flex;
    flex-direction: column;
  }

  .empty-state {
    opacity: 0.7;
    font-size: 16px;
  }

  /* Below this width, the two-column layout gets cramped — fall back to
     showing the editor as a full-screen overlay instead of squeezing it,
     and only when it actually has a button to edit. Otherwise leave it
     out of the layout entirely so the preview gets the full canvas. */
  @media (max-width: 700px) {
    .app-body {
      position: relative;
    }

    .editor-pane:not(.active) {
      display: none;
    }

    .editor-pane.active {
      /* Fills .app-body (its position:relative ancestor) — which already
         starts below the header — so no header-height magic number. */
      position: absolute;
      inset: 0;
      background: var(--neutral-600);
      z-index: 10;
    }
  }
</style>
