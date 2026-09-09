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

  // Resolves a Page id + folder-drill path down to the actual buttons array
  // it points at. Used both for the live `visibleButtons` (current nav
  // state) and for saves pinned to a *captured* path (see saveButtonAt) so
  // an open editor's autosave always lands where the button actually lives,
  // even if navigation has since moved on elsewhere.
  private buttonsAt(pageId: string | null, folderPath: string[]): Button[] {
    const page = this.activeProfile?.pages.find((p) => p.id === pageId);
    let buttons = page?.buttons ?? [];
    for (const folderId of folderPath) {
      const folder = buttons.find((b) => b.id === folderId);
      if (!folder || folder.content.type !== "folder") break;
      buttons = folder.content.buttons;
    }
    return buttons;
  }

  // The buttons array currently on screen: the current Page's buttons, or —
  // once folderStack is non-empty — whichever nested Folder's own buttons
  // array that stack currently points at.
  get visibleButtons(): Button[] {
    return this.buttonsAt(this.currentPageId, this.folderStack);
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

  // Pinned to an explicit (pageId, folderPath) rather than the live
  // navigation state — an editor captures that path once, when it opens, so
  // its save always targets wherever the button actually lives regardless
  // of whatever else navigates around it while the editor is still open.
  async saveButtonAt(pageId: string | null, folderPath: string[], button: Button) {
    const buttons = this.buttonsAt(pageId, folderPath);
    const existing = buttons.findIndex((b) => b.id === button.id);
    if (existing >= 0) buttons[existing] = button;
    else buttons.push(button);
    await this.persist();
  }

  async removeButtonAt(pageId: string | null, folderPath: string[], id: string) {
    const buttons = this.buttonsAt(pageId, folderPath);
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
