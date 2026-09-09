import { invoke } from "@tauri-apps/api/core";
import type { Button, Config, Page, Profile } from "$lib/types/button";

// Matches the original Stream Deck's own Page cap — kept simple rather than
// building a navigation UI that scales past what's actually usable to swipe
// through.
export const MAX_PAGES = 10;

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

  // Falls back to a positional "Page N" label — named pages are a real
  // feature (a page-name concept the original Stream Deck doesn't have at
  // all), but most pages will stay unnamed, and the pager itself is
  // deliberately just numbers to stay compact.
  get currentPageLabel(): string {
    const page = this.currentPage;
    if (!page) return "";
    if (page.name) return page.name;
    const index = this.activeProfile?.pages.findIndex((p) => p.id === page.id) ?? 0;
    return `Page ${index + 1}`;
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

  // Switching Profile is a lateral move, same as switching Page — it resets
  // to that Profile's first Page, not another level of the folder stack.
  async switchProfile(id: string) {
    if (!this.config) return;
    this.config.activeProfileId = id;
    this.currentPageId = this.activeProfile?.pages[0]?.id ?? null;
    this.folderStack = [];
    await this.persist();
  }

  async createProfile(name: string) {
    if (!this.config) return;
    const profile: Profile = {
      id: crypto.randomUUID(),
      name,
      pages: [{ id: crypto.randomUUID(), name: undefined, buttons: [] }],
    };
    this.config.profiles.push(profile);
    await this.switchProfile(profile.id);
  }

  async renameProfile(id: string, name: string) {
    const profile = this.config?.profiles.find((p) => p.id === id);
    if (!profile) return;
    profile.name = name;
    await this.persist();
  }

  // Blocks deleting the last remaining Profile — there must always be at
  // least one. If the deleted Profile was active, switches to whichever one
  // is now first rather than requiring the caller to switch away first, so
  // activeProfileId is never left pointing at a Profile that's gone.
  async deleteProfile(id: string) {
    if (!this.config || this.config.profiles.length <= 1) return;
    const index = this.config.profiles.findIndex((p) => p.id === id);
    if (index < 0) return;
    const wasActive = this.config.activeProfileId === id;
    this.config.profiles.splice(index, 1);
    if (wasActive) {
      await this.switchProfile(this.config.profiles[0].id);
    } else {
      await this.persist();
    }
  }

  async addPage(name?: string) {
    const profile = this.activeProfile;
    if (!profile || profile.pages.length >= MAX_PAGES) return;
    const page: Page = { id: crypto.randomUUID(), name, buttons: [] };
    profile.pages.push(page);
    this.selectPage(page.id);
    await this.persist();
  }

  async renamePage(id: string, name: string) {
    const page = this.activeProfile?.pages.find((p) => p.id === id);
    if (!page) return;
    page.name = name.trim() || undefined;
    await this.persist();
  }

  // Blocks removing the last remaining Page in a Profile — same "always at
  // least one" invariant Profiles themselves carry, and matches how every
  // Profile is bootstrapped with exactly one Page.
  async removePage(id: string) {
    const profile = this.activeProfile;
    if (!profile || profile.pages.length <= 1) return;
    const index = profile.pages.findIndex((p) => p.id === id);
    if (index < 0) return;
    const wasCurrent = this.currentPageId === id;
    profile.pages.splice(index, 1);
    if (wasCurrent) {
      this.selectPage(profile.pages[0].id);
    }
    await this.persist();
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
