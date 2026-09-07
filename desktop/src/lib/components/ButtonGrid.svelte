<script lang="ts">
  import { mockButtons } from "$lib/data/mockButtons";
</script>

<div class="button-grid">
  {#each mockButtons as button (button.id)}
    <button class="grid-button" type="button">
      {#if button.icon}
        <span class="icon">{button.icon}</span>
      {/if}
      {#if button.label}
        <span class="label">{button.label}</span>
      {/if}
    </button>
  {/each}
</div>

<style>
  .button-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(96px, 1fr));
    gap: 12px;
    padding: 16px;
  }

  .grid-button {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 6px;
    aspect-ratio: 1;
    border-radius: 12px;
    border: 1px solid rgba(0, 0, 0, 0.1);
    background-color: #ffffff;
    box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);
    cursor: pointer;
    transition:
      border-color 0.2s,
      background-color 0.2s;
  }

  .grid-button:hover {
    border-color: #396cd8;
  }

  .grid-button:active {
    background-color: #e8e8e8;
  }

  .icon {
    font-size: 1.75rem;
    line-height: 1;
  }

  .label {
    font-size: 0.75rem;
    text-align: center;
    color: inherit;
  }

  @media (prefers-color-scheme: dark) {
    .grid-button {
      background-color: #0f0f0f98;
      border-color: rgba(255, 255, 255, 0.1);
      color: #f6f6f6;
    }

    .grid-button:active {
      background-color: #0f0f0f69;
    }
  }
</style>
