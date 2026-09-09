import { invoke } from "@tauri-apps/api/core";
import type { Button, Config, Page, Profile } from "$lib/types/button";

class ConfigStore {
  config = $state<Config | null>(null);

  // UI-local navigation state — never persisted. currentPageId selects among
  // the active Profile's Pages; folderStack holds the ids of Folder buttons
  // drilled into so far, deepest last.
  currentPageId = $state<string | null>(null);
  folderStack = $state<string[]>([]);

  get activeProfile(): Profile | null {
    if (!this.config) return null;
    return this.config.profiles.find((p) => p.id === this.config!.activeProfileId) ?? null;
  }

  get currentPage(): Page | null {
    const profile = this.activeProfile;
    if (!profile) return null;
    return profile.pages.find((p) => p.id === this.currentPageId) ?? null;
  }

  // The buttons array currently on screen: the current Page's buttons, or —
  // once folderStack is non-empty — whichever nested Folder's own buttons
  // array that stack currently points at.
  get visibleButtons(): Button[] {
    let buttons = this.currentPage?.buttons ?? [];
    for (const folderId of this.folderStack) {
      const folder = buttons.find((b) => b.id === folderId);
      if (!folder || folder.content.type !== "folder") break;
      buttons = folder.content.buttons;
    }
    return buttons;
  }

  async load() {
    this.config = await invoke<Config>("get_config");
    this.currentPageId = this.activeProfile?.pages[0]?.id ?? null;
    this.folderStack = [];
  }

  selectPage(pageId: string) {
    this.currentPageId = pageId;
    this.folderStack = [];
  }

  enterFolder(button: Button) {
    if (button.content.type !== "folder") return;
    this.folderStack = [...this.folderStack, button.id];
  }

  exitFolder() {
    this.folderStack = this.folderStack.slice(0, -1);
  }

  private async persist() {
    if (!this.config) return;
    await invoke("save_config", { config: this.config });
  }

  async saveButton(button: Button) {
    const buttons = this.visibleButtons;
    const existing = buttons.findIndex((b) => b.id === button.id);
    if (existing >= 0) buttons[existing] = button;
    else buttons.push(button);
    await this.persist();
  }

  async removeButton(id: string) {
    const buttons = this.visibleButtons;
    const index = buttons.findIndex((b) => b.id === id);
    if (index >= 0) buttons.splice(index, 1);
    await this.persist();
  }

  async reorderButtons(order: string[]) {
    const buttons = this.visibleButtons;
    const reordered = order
      .map((id) => buttons.find((b) => b.id === id))
      .filter((b): b is Button => b !== undefined);
    buttons.splice(0, buttons.length, ...reordered);
    await this.persist();
  }
}

export const configStore = new ConfigStore();
