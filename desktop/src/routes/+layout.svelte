<script lang="ts">
  import ConfirmDialog from "$lib/components/ConfirmDialog.svelte";

  let { children } = $props();
</script>

{@render children()}

<!-- One instance for the whole app; driven by $lib/stores/confirm.svelte. -->
<ConfirmDialog />
