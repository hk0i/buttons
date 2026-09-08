<script lang="ts">
  import type { MediaKeyKind } from "$lib/types/button";

  let { key = $bindable<MediaKeyKind>("playPause") }: { key?: MediaKeyKind } = $props();
</script>

<select bind:value={key}>
  <option value="playPause">Play/Pause</option>
  <option value="mute">Mute</option>
  <option value="nextTrack">Next Track</option>
  <option value="previousTrack">Previous Track</option>
</select>

<style>
  select {
    flex: 1;
    padding: 6px 10px;
  }
</style>
