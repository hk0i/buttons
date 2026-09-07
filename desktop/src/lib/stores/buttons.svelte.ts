import { invoke } from "@tauri-apps/api/core";
import type { Button } from "$lib/types/button";

class ButtonStore {
  buttons = $state<Button[]>([]);

  async load() {
    this.buttons = await invoke<Button[]>("list_buttons");
  }

  async save(button: Button) {
    await invoke("save_button", { button });
    await this.load();
  }

  async remove(id: string) {
    await invoke("delete_button", { id });
    await this.load();
  }

  async reorder(order: string[]) {
    await invoke("reorder_buttons", { order });
    await this.load();
  }
}

export const buttonStore = new ButtonStore();
