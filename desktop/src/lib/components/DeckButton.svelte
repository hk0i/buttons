<script lang="ts">
  let { icon, label, selected = false }: { icon?: string; label?: string; selected?: boolean } = $props();
</script>

<div class="deck-button" class:selected>
  {#if icon}
    <span class="icon">{icon}</span>
  {/if}
  {#if label}
    <span class="label">{label}</span>
  {/if}
</div>

<style>
  .deck-button {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 6px;
    width: 100%;
    height: 100%;
    aspect-ratio: 1;
    border-radius: 8px;
    border: 2px solid transparent;
    background-color: var(--neutral-300);
    box-sizing: border-box;
    overflow: hidden;
  }

  .deck-button.selected {
    border-color: var(--primary-700);
  }

  .icon {
    font-size: 1.5rem;
    line-height: 1;
  }

  .label {
    font-size: 0.65rem;
    text-align: center;
    color: var(--secondary-700);
    word-break: break-word;
    padding: 0 4px;
  }
</style>
