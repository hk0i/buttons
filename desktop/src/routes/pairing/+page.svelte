<script lang="ts">
  import "$lib/styles/tokens.css";
  import { onMount } from "svelte";
  import { invoke } from "@tauri-apps/api/core";
  import { resolve } from "$app/paths";

  // Mirrors pairing.rs's ONE_TIME_TOKEN_TTL — client-side timer only, not
  // polled from the backend. "expires in ~90s" is enough per the spec;
  // an exact server-driven countdown isn't required.
  const TOKEN_TTL_MS = 90_000;

  let svg = $state<string | null>(null);
  let isExpired = $state(false);
  let error = $state<string | null>(null);
  let expireTimer: ReturnType<typeof setTimeout> | undefined;

  // window.prompt() doesn't render in Tauri's WKWebView — inline edit,
  // same pattern as ProfileSwitcher.svelte's create/rename fields, not a
  // blocking dialog. See docs/slices/07c. Desktop Device Name.spec.md.
  let deviceName = $state<string | null>(null);
  let isEditingName = $state(false);
  let draftName = $state("");

  async function requestNewCode() {
    clearTimeout(expireTimer);
    error = null;
    isExpired = false;
    svg = null;
    try {
      const qr = await invoke<{ svg: string; payload: string }>("get_pairing_qr");
      svg = qr.svg;
      expireTimer = setTimeout(() => {
        isExpired = true;
      }, TOKEN_TTL_MS);
    } catch (e) {
      error = String(e);
    }
  }

  async function loadDeviceName() {
    deviceName = await invoke<string>("get_device_name");
  }

  function startEditingName() {
    isEditingName = true;
    draftName = deviceName ?? "";
  }

  function cancelEditingName() {
    isEditingName = false;
    draftName = "";
  }

  async function confirmEditingName() {
    const name = draftName.trim();
    if (!name) return cancelEditingName();
    await invoke("set_device_name", { name });
    deviceName = name;
    cancelEditingName();
  }

  function focusOnMount(node: HTMLInputElement) {
    node.focus();
  }

  onMount(() => {
    requestNewCode();
    loadDeviceName();
    return () => clearTimeout(expireTimer);
  });
</script>

<div class="pairing">
  <div class="pairing-header">
    <h1>Pair a device</h1>
    <!-- The only way back — mouse/trackpad "back" gesture is browser
         behavior this app shouldn't rely on as the sole exit. -->
    <a class="close-link" href={resolve("/")} aria-label="Close">✕</a>
  </div>

  <div class="device-name">
    {#if isEditingName}
      <input
        type="text"
        bind:value={draftName}
        placeholder="Desktop name"
        maxlength="63"
        use:focusOnMount
        onkeydown={(e) => {
          if (e.key === "Enter") confirmEditingName();
          else if (e.key === "Escape") cancelEditingName();
        }}
      />
      <button type="button" onclick={confirmEditingName} title="Confirm">✓</button>
      <button type="button" onclick={cancelEditingName} title="Cancel">✕</button>
    {:else}
      <span class="device-name-label">{deviceName ?? "…"}</span>
      <button type="button" onclick={startEditingName} title="Rename this desktop">✎</button>
    {/if}
  </div>

  {#if error}
    <p class="status error">{error}</p>
  {:else if svg}
    <!-- Server-rendered SVG (qrcode crate) — no client-side QR library,
         per Scope -> In item 7. -->
    <div class="qr" class:expired={isExpired} aria-hidden={isExpired}>
      {@html svg}
    </div>
    {#if isExpired}
      <p class="status">This code expired.</p>
      <button onclick={requestNewCode}>Generate new code</button>
    {:else}
      <p class="status">Scan with the Buttons mobile app — expires in ~90s.</p>
      <p class="status">Waiting for connection…</p>
    {/if}
  {/if}
</div>

<style>
  .pairing {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 12px;
    padding: 32px 16px;
    height: 100vh;
    box-sizing: border-box;
    background: var(--neutral-600);
    color: var(--key-white);
    font-family: var(--font-body);
  }

  .pairing-header {
    width: 100%;
    max-width: 400px;
    display: flex;
    align-items: center;
    justify-content: center;
    position: relative;
  }

  h1 {
    font-family: var(--font-heading);
    font-weight: 700;
    font-size: 24px;
    margin: 0;
  }

  .close-link {
    position: absolute;
    right: 0;
    color: var(--key-white);
    text-decoration: none;
    opacity: 0.7;
    font-size: 18px;
    line-height: 1;
    padding: 4px 8px;
    border-radius: 4px;
  }

  .close-link:hover {
    opacity: 1;
    background: var(--neutral-500);
  }

  .device-name {
    width: 100%;
    max-width: 400px;
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 6px;
  }

  .device-name-label {
    opacity: 0.85;
    font-size: 14px;
  }

  .device-name input {
    flex: 1;
    min-width: 0;
    max-width: 240px;
    padding: 4px 8px;
    background: var(--neutral-500);
    border: 1px solid var(--neutral-700);
    color: var(--key-white);
    border-radius: 4px;
    font-family: var(--font-body);
    font-size: 14px;
    height: 28px;
    box-sizing: border-box;
  }

  .device-name button {
    background: var(--neutral-500);
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

  .qr {
    background: var(--key-white);
    padding: 16px;
    border-radius: 8px;
    /* Visibly replaced/dimmed at expiry, not left looking scannable —
       Scope -> In item 7's "Expired" state. */
    transition: opacity 0.2s ease;
  }

  .qr.expired {
    opacity: 0.25;
  }

  .qr :global(svg) {
    display: block;
    width: 240px;
    height: 240px;
  }

  .status {
    margin: 0;
    opacity: 0.85;
    font-size: 14px;
  }

  .status.error {
    color: var(--primary-700);
  }
</style>
