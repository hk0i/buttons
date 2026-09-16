import { invoke } from "@tauri-apps/api/core";
import { listen, type UnlistenFn } from "@tauri-apps/api/event";
import type { Button, SwitchState } from "$lib/types/button";

// Matches server.rs's SWITCH_STATES_CHANGED_EVENT constant.
const SWITCH_STATES_CHANGED_EVENT = "switch-states-changed";

// Mirrors desktop's own SwitchStates (button_id -> is "on" showing) —
// deliberately not part of ConfigStore/Config, same separation the Rust
// side keeps between buttons.json (authored config) and switch_state.json
// (local runtime state). Loads once via get_switch_states, then stays live
// via the switch-states-changed event server::execute_press emits after
// every successful flip (a real press or the editor's Test button). See
// slice 09 spec, § Files to Touch #9.
class SwitchStatesStore {
  states = $state<Record<string, boolean>>({});
  private unlisten: UnlistenFn | null = null;

  async load() {
    this.states = await invoke<Record<string, boolean>>("get_switch_states");
    // Listener is set up once, on first load — a second load() call (e.g. a
    // future profile switch that re-fetches) shouldn't stack duplicate
    // listeners.
    if (!this.unlisten) {
      this.unlisten = await listen<Record<string, boolean>>(SWITCH_STATES_CHANGED_EVENT, (event) => {
        this.states = event.payload;
      });
    }
  }

  // Absent means off, matching switch_state.json's own default (a button
  // with no recorded press yet).
  isOn(buttonId: string): boolean {
    return this.states[buttonId] ?? false;
  }

  // Resolves a button's currently-showing SwitchState directly, so callers
  // read imperatively (currentState(button)?.label) instead of re-deriving
  // "which of off/on is showing" from isOn() at every render site. undefined
  // for anything that isn't a .switch button (including no button at all).
  currentState(button: Button | undefined): SwitchState | undefined {
    if (button?.content.type !== "switch") return undefined;
    return this.isOn(button.id) ? button.content.on : button.content.off;
  }
}

export const switchStatesStore = new SwitchStatesStore();
