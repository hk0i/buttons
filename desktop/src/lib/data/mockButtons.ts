export interface MockButton {
  id: string;
  label?: string;
  icon?: string; // path or data URI
}

export const mockButtons: MockButton[] = [
  { id: "1", label: "Mute", icon: "🔇" },
  { id: "2", label: "Scene 1", icon: "🎬" },
  { id: "3", label: "Record", icon: "⏺️" },
  { id: "4", label: "Screenshot", icon: "📸" },
  { id: "5", label: "Timer", icon: "⏱️" },
  { id: "6", label: "Lights", icon: "💡" },
  { id: "7", label: "Music", icon: "🎵" },
  { id: "8", label: "Chat", icon: "💬" },
];
