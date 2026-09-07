export interface Button {
  id: string;
  label?: string;
  icon?: string; // emoji/text glyph, per slice 2's convention
  actions: Action[];
}

export type Action =
  | { type: "launchApp"; path: string }
  | { type: "hotkey"; keys: string[] } // e.g. ["cmd", "shift", "s"]; F13-F24 by name
  | { type: "mediaKey"; key: MediaKeyKind };

export type MediaKeyKind = "playPause" | "mute" | "nextTrack" | "previousTrack";
