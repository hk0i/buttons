// Hand-written mock data driving the static UI (slice 05).
//
// Scaffolding: superseded by real config_sync data at step 7. See
// docs/slices/05. Mobile Grid UI Static.spec.md § Type lifecycle.

extension Button {
    /// A regular action button.
    static func action(
        _ id: String,
        _ label: String,
        _ icon: String,
        _ actions: [Action] = [],
    ) -> Button {
        Button(id: id, label: label, icon: icon, content: .actions(actions))
    }

    /// A folder button whose nested grid always opens with a Back cell at
    /// index 0 — the desktop config's invariant (slice 4). Callers pass only
    /// the user-authored buttons; the Back cell is prepended here.
    static func folder(
        _ id: String,
        _ label: String,
        _ icon: String,
        contents: [Button],
    ) -> Button {
        Button(
            id: id,
            label: label,
            icon: icon,
            content: .folder([.back("\(id).back")] + contents),
        )
    }

    /// The Back cell. Locked/non-editable this slice — nil label/icon, so the
    /// view falls back to ⬅ / "Back".
    static func back(_ id: String) -> Button {
        Button(id: id, label: nil, icon: nil, content: .back)
    }
}

enum MockConfig {
    static let config = Config(
        profiles: [streaming],
        activeProfileId: streaming.id,
    )

    private static let streaming = Profile(
        id: "profile.streaming",
        name: "Streaming",
        pages: [scenesPage, mediaPage, appsPage],
    )

    // Page 1 — actions plus a folder that itself contains a nested folder
    // (two levels deep, per the spec).
    private static let scenesPage = Page(
        id: "page.scenes",
        name: "Scenes",
        buttons: [
            .action("btn.live", "Go Live", "🔴", [.hotkey(keys: ["cmd", "1"])]),
            .action("btn.brb", "BRB", "☕️", [.hotkey(keys: ["cmd", "2"])]),
            .action("btn.mute", "Mute", "🔇", [.mediaKey(key: .mute)]),
            .folder("folder.cameras", "Cameras", "🎥", contents: [
                .action("btn.cam.front", "Front", "🤳", [.hotkey(keys: ["cmd", "shift", "1"])]),
                .action("btn.cam.desk", "Desk", "🖥️", [.hotkey(keys: ["cmd", "shift", "2"])]),
                .folder("folder.presets", "Presets", "⭐️", contents: [
                    .action("btn.preset.wide", "Wide", "↔️", [.hotkey(keys: ["cmd", "shift", "w"])]),
                    .action("btn.preset.close", "Close-up", "🔍", [.hotkey(keys: ["cmd", "shift", "c"])]),
                ]),
            ]),
        ],
    )

    // Page 2 — media keys.
    private static let mediaPage = Page(
        id: "page.media",
        name: "Media",
        buttons: [
            .action("btn.playpause", "Play / Pause", "⏯️", [.mediaKey(key: .playPause)]),
            .action("btn.prev", "Previous", "⏮️", [.mediaKey(key: .previousTrack)]),
            .action("btn.next", "Next", "⏭️", [.mediaKey(key: .nextTrack)]),
        ],
    )

    // Page 3 — launch-app actions; one button intentionally has no label to
    // exercise the icon-only cell.
    private static let appsPage = Page(
        id: "page.apps",
        name: nil,
        buttons: [
            .action("btn.app.obs", "OBS", "🎬", [.launchApp(path: "/Applications/OBS.app")]),
            .action("btn.app.discord", "Discord", "💬", [.launchApp(path: "/Applications/Discord.app")]),
            Button(
                id: "btn.app.terminal",
                label: nil,
                icon: "⌨️",
                content: .actions([.launchApp(path: "/System/Applications/Utilities/Terminal.app")]),
            ),
        ],
    )
}
