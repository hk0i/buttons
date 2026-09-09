export interface Config {
  profiles: Profile[];
  activeProfileId: string;
}

export interface Profile {
  id: string;
  name: string;
  pages: Page[];
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
  | { type: "back" }; // no payload; pops one level off the nav stack

export type Action =
  | { type: "launchApp"; path: string }
  | { type: "hotkey"; keys: string[] } // e.g. ["cmd", "shift", "s"]; F13-F24 by name
  | { type: "mediaKey"; key: MediaKeyKind };

export type MediaKeyKind = "playPause" | "mute" | "nextTrack" | "previousTrack";
