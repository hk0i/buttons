import XCTest
@testable import ButtonsProto

/// Codegen + round-trip prototype only — see
/// `docs/slices/06. Protobuf Codegen Prototype.spec.md`. Mirrors
/// `verify-rust`'s test cases so the same presence properties are checked
/// in both languages.
final class RoundTripTests: XCTestCase {

    private func sampleConfig() -> Buttons_Config {
        var recordHotkey = Buttons_Hotkey()
        recordHotkey.keys = ["cmd", "shift", "r"]

        var muteAction = Buttons_Action()
        muteAction.action = .mediaKey(.mute)

        var hotkeyAction = Buttons_Action()
        hotkeyAction.action = .hotkey(recordHotkey)

        var recordActions = Buttons_ActionList()
        recordActions.actions = [hotkeyAction, muteAction]

        var recordButton = Buttons_Button()
        recordButton.id = "b1"
        recordButton.label = "Record"
        recordButton.icon = "🔴"
        recordButton.content = .actions(recordActions)

        var backButton = Buttons_Button()
        backButton.id = "b2-back"
        backButton.content = .back(Buttons_Back())

        var launchApp = Buttons_LaunchApp()
        launchApp.path = "/Applications/OBS.app"
        var launchAction = Buttons_Action()
        launchAction.action = .launchApp(launchApp)
        var launchActions = Buttons_ActionList()
        launchActions.actions = [launchAction]

        var launchButton = Buttons_Button()
        launchButton.id = "b2-1"
        launchButton.label = "Launch OBS"
        launchButton.content = .actions(launchActions)

        var folder = Buttons_FolderContent()
        folder.buttons = [backButton, launchButton]

        var toolsButton = Buttons_Button()
        toolsButton.id = "b2"
        toolsButton.label = "Tools"
        toolsButton.content = .folder(folder)

        var page = Buttons_Page()
        page.id = "pg1"
        page.name = "Main"
        page.buttons = [recordButton, toolsButton]

        var profile = Buttons_Profile()
        profile.id = "p1"
        profile.name = "Streaming"
        profile.pages = [page]

        var config = Buttons_Config()
        config.profiles = [profile]
        config.activeProfileID = "p1" // swift-protobuf capitalizes the "Id" acronym as "ID"

        return config
    }

    func testRoundTripPreservesFullConfig() throws {
        let original = sampleConfig()
        let bytes = try original.serializedData()
        let decoded = try Buttons_Config(serializedBytes: bytes)
        XCTAssertEqual(original, decoded)
    }

    /// Presence case 1: nil-vs-empty-string must stay distinguishable
    /// through the round trip (spec finding 3).
    func testRoundTripDistinguishesAbsentLabelFromEmptyLabel() throws {
        var absent = Buttons_Button()
        absent.id = "absent"
        absent.content = .back(Buttons_Back())

        var empty = Buttons_Button()
        empty.id = "empty"
        empty.label = ""
        empty.content = .back(Buttons_Back())

        let absentDecoded = try Buttons_Button(serializedBytes: absent.serializedData())
        let emptyDecoded = try Buttons_Button(serializedBytes: empty.serializedData())

        XCTAssertFalse(absentDecoded.hasLabel)
        XCTAssertTrue(emptyDecoded.hasLabel)
        XCTAssertEqual(emptyDecoded.label, "")
    }

    /// Presence case 2: a `.back`-set `content` must stay distinguishable
    /// from an unset `content` oneof (spec finding 1 / Implementation
    /// Notes item 4).
    func testRoundTripDistinguishesBackCaseFromUnsetOneof() throws {
        var backSet = Buttons_Button()
        backSet.id = "back"
        backSet.content = .back(Buttons_Back())

        var unset = Buttons_Button()
        unset.id = "unset"
        // content left nil — no case selected

        let backDecoded = try Buttons_Button(serializedBytes: backSet.serializedData())
        let unsetDecoded = try Buttons_Button(serializedBytes: unset.serializedData())

        guard case .back = backDecoded.content else {
            XCTFail("expected .back case, got \(String(describing: backDecoded.content))")
            return
        }
        XCTAssertNil(unsetDecoded.content)
    }
}
