pub struct MockButton {
    pub id: &'static str,
    pub label: &'static str,
    pub icon: &'static str,
}

pub const MOCK_BUTTONS: &[MockButton] = &[
    MockButton { id: "1", label: "Mute", icon: "🔇" },
    MockButton { id: "2", label: "Scene 1", icon: "🎬" },
    MockButton { id: "3", label: "Record", icon: "⏺️" },
    MockButton { id: "4", label: "Screenshot", icon: "📸" },
    MockButton { id: "5", label: "Timer", icon: "⏱️" },
    MockButton { id: "6", label: "Lights", icon: "💡" },
    MockButton { id: "7", label: "Music", icon: "🎵" },
    MockButton { id: "8", label: "Chat", icon: "💬" },
];
