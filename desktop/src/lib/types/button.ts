export interface Config {
  profiles: Profile[];
  activeProfileId: string;
}

export interface Profile {
  id: string;
  name: string;
  pages: Page[];
  associatedAppByPlatform: Partial<Record<"macos" | "windows", string>>;
}

export interface Page {
  id: string;
  name?: string;
  buttons: Button[];
}

export interface Button {
  id: string;
  label?: string;
  icon?: string; // emoji/text glyph, per slice 2's convention
  content: ButtonContent;
}

export type ButtonContent =
  | { type: "actions"; actions: Action[] }
  | { type: "folder"; buttons: Button[] } // buttons[0] is always Back
  | { type: "back" } // no payload; pops one level off the nav stack
  // Two-state toggle, capped at two states (matching Elgato's own "Multi
  // Action Switch" limit) — see slice 09 spec Scope → Out #3. `Button`
  // itself gains no new field — no TS mirror of the wire's `is_active`,
  // which is local-Rust-only (slice 09 spec, § Files to Touch #8).
  | { type: "switch"; off: SwitchState; on: SwitchState };

// Mirrors `Button`'s own `label`/`icon` shape plus a bare `actions` list —
// matches `config.rs`'s `SwitchState` and the wire `SwitchState` exactly.
export interface SwitchState {
  label?: string;
  icon?: string;
  actions: Action[];
}

export type Action =
  | { type: "launchApp"; path: string }
  | { type: "hotkey"; keys: string[] } // e.g. ["cmd", "shift", "s"]; F13-F24 by name
  | { type: "mediaKey"; key: MediaKeyKind };

export type MediaKeyKind = "playPause" | "mute" | "nextTrack" | "previousTrack";
