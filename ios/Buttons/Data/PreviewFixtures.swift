// Preview/test fixture data — one shared source backing every `#Preview`
// block (`DeckView`, `PageGrid`, `ButtonGrid`, `DeckButton`) and reusable
// later for `XCTest` view-logic tests that don't need a real connection.
// Renamed + rewritten from `MockConfig.swift` (slice 05) at slice 07 —
// same fixture shape (2-level folders, every action kind, the nil-label/
// nil-name edge cases), rebuilt against `Buttons_Config`/`Buttons_Button`
// instead of the now-deleted `ButtonModel`.

extension Buttons_Profile {
    init(id: String, name: String, pages: [Buttons_Page]) {
        self.init()
        self.id = id
        self.name = name
        self.pages = pages
    }
}

extension Buttons_Page {
    /// `name: nil` leaves the field unset (`hasName == false`) — real
    /// devices must render the fallback ("Back" / icon-only), not an
    /// empty string, when this field is absent on the wire.
    init(id: String, name: String?, buttons: [Buttons_Button]) {
        self.init()
        self.id = id
        if let name {
            self.name = name
        }
        self.buttons = buttons
    }
}

extension Buttons_Button {
    /// A regular action button.
    static func action(
        _ id: String,
        _ label: String,
        _ icon: String,
        _ actions: [Buttons_Action] = []
    ) -> Buttons_Button {
        var button = Buttons_Button()
        button.id = id
        button.label = label
        button.icon = icon
        var list = Buttons_ActionList()
        list.actions = actions
        button.content = .actions(list)
        return button
    }

    /// A folder button whose nested grid always opens with a Back cell at
    /// index 0 — the desktop config's invariant (slice 4). Callers pass
    /// only the user-authored buttons; the Back cell is prepended here.
    static func folder(
        _ id: String,
        _ label: String,
        _ icon: String,
        contents: [Buttons_Button]
    ) -> Buttons_Button {
        var button = Buttons_Button()
        button.id = id
        button.label = label
        button.icon = icon
        var folderContent = Buttons_FolderContent()
        folderContent.buttons = [.back("\(id).back")] + contents
        button.content = .folder(folderContent)
        return button
    }

    /// The Back cell. Locked/non-editable this slice — no label/icon set
    /// (`hasLabel`/`hasIcon` both false), so the view falls back to
    /// ⬅️ / "Back".
    static func back(_ id: String) -> Buttons_Button {
        var button = Buttons_Button()
        button.id = id
        button.content = .back(Buttons_Back())
        return button
    }
}

extension Buttons_Action {
    static func hotkey(keys: [String]) -> Buttons_Action {
        var action = Buttons_Action()
        var hotkey = Buttons_Hotkey()
        hotkey.keys = keys
        action.action = .hotkey(hotkey)
        return action
    }

    static func mediaKey(_ key: Buttons_MediaKeyKind) -> Buttons_Action {
        var action = Buttons_Action()
        action.action = .mediaKey(key)
        return action
    }

    static func launchApp(path: String) -> Buttons_Action {
        var action = Buttons_Action()
        var launchApp = Buttons_LaunchApp()
        launchApp.path = path
        action.action = .launchApp(launchApp)
        return action
    }
}

enum PreviewFixtures {
    static let config: Buttons_Config = {
        var config = Buttons_Config()
        config.profiles = [streaming]
        config.activeProfileID = streaming.id
        return config
    }()

    private static let streaming = Buttons_Profile(
        id: "profile.streaming",
        name: "Streaming",
        pages: [scenesPage, mediaPage, appsPage]
    )

    // Page 1 — actions plus a folder that itself contains a nested folder
    // (two levels deep, per the spec).
    private static let scenesPage = Buttons_Page(
        id: "page.scenes",
        name: "Scenes",
        buttons: [
            .action("btn.live", "Go Live", "🔴", [.hotkey(keys: ["cmd", "1"])]),
            .action("btn.brb", "BRB", "☕️", [.hotkey(keys: ["cmd", "2"])]),
            .action("btn.mute", "Mute", "🔇", [.mediaKey(.mute)]),
            .folder(
                "folder.cameras", "Cameras", "🎥",
                contents: [
                    .action("btn.cam.front", "Front", "🤳", [.hotkey(keys: ["cmd", "shift", "1"])]),
                    .action("btn.cam.desk", "Desk", "🖥️", [.hotkey(keys: ["cmd", "shift", "2"])]),
                    .folder(
                        "folder.presets", "Presets", "⭐️",
                        contents: [
                            .action(
                                "btn.preset.wide", "Wide", "↔️",
                                [.hotkey(keys: ["cmd", "shift", "w"])]),
                            .action(
                                "btn.preset.close", "Close-up", "🔍",
                                [.hotkey(keys: ["cmd", "shift", "c"])]),
                        ]),
                ]),
        ]
    )

    // Page 2 — media keys.
    private static let mediaPage = Buttons_Page(
        id: "page.media",
        name: "Media",
        buttons: [
            .action("btn.playpause", "Play / Pause", "⏯️", [.mediaKey(.playPause)]),
            .action("btn.prev", "Previous", "⏮️", [.mediaKey(.previousTrack)]),
            .action("btn.next", "Next", "⏭️", [.mediaKey(.nextTrack)]),
        ]
    )

    // Page 3 — launch-app actions; nil name exercises the tab-less-title
    // edge case, and one button intentionally has no label to exercise
    // the icon-only cell.
    private static let appsPage = Buttons_Page(
        id: "page.apps",
        name: nil,
        buttons: [
            .action("btn.app.obs", "OBS", "🎬", [.launchApp(path: "/Applications/OBS.app")]),
            .action(
                "btn.app.discord", "Discord", "💬", [.launchApp(path: "/Applications/Discord.app")]),
            terminalButton,
        ]
    )

    private static let terminalButton: Buttons_Button = {
        var button = Buttons_Button()
        button.id = "btn.app.terminal"
        button.icon = "⌨️"
        var actions = Buttons_ActionList()
        actions.actions = [.launchApp(path: "/System/Applications/Utilities/Terminal.app")]
        button.content = .actions(actions)
        return button
    }()
}
