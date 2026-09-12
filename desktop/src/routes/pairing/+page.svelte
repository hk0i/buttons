<script lang="ts">
  import "$lib/styles/tokens.css";
  import { onMount } from "svelte";
  import { invoke } from "@tauri-apps/api/core";

  // Mirrors pairing.rs's ONE_TIME_TOKEN_TTL — client-side timer only, not
  // polled from the backend. "expires in ~90s" is enough per the spec;
  // an exact server-driven countdown isn't required.
  const TOKEN_TTL_MS = 90_000;

  let svg = $state<string | null>(null);
  let isExpired = $state(false);
  let error = $state<string | null>(null);
  let expireTimer: ReturnType<typeof setTimeout> | undefined;

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

  onMount(() => {
    requestNewCode();
    return () => clearTimeout(expireTimer);
  });
</script>

<div class="pairing">
  <h1>Pair a device</h1>

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
      <p class="status">Scan with the Buttons iOS app — expires in ~90s.</p>
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

  h1 {
    font-family: var(--font-heading);
    font-weight: 700;
    font-size: 24px;
    margin: 0;
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
