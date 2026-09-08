<script lang="ts">
  import { open } from "@tauri-apps/plugin-dialog";

  let { path = $bindable("") }: { path?: string } = $props();

  async function pickAppPath() {
    // directory: false is deliberate — on macOS, NSOpenPanel still lets you
    // pick a .app bundle this way since it treats bundles as packages, not
    // browsable folders.
    const picked = await open({ directory: false, multiple: false });
    if (picked) path = picked;
  }
</script>

<input type="text" bind:value={path} placeholder="/path/to/app" />
<button type="button" onclick={pickAppPath}>Browse…</button>

<style>
  input {
    flex: 1;
    padding: 6px 10px;
  }
</style>
