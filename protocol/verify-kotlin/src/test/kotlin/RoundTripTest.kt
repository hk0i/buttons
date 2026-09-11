// Codegen + round-trip prototype only — see
// docs/slices/06. Protobuf Codegen Prototype.spec.md. Mirrors
// verify-rust/verify-swift's test cases so the same presence properties are
// checked in all three languages.

package buttons

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertNotNull
import kotlin.test.assertNotEquals

class RoundTripTest {

    private fun sampleConfig(): Config {
        val recordButton = Button(
            id = "b1",
            label = "Record",
            icon = "🔴", // 🔴
            actions = ActionList(
                actions = listOf(
                    Action(hotkey = Hotkey(keys = listOf("cmd", "shift", "r"))),
                    Action(media_key = MediaKeyKind.MEDIA_KEY_KIND_MUTE),
                ),
            ),
        )

        val backButton = Button(id = "b2-back", back = Back())
        val launchButton = Button(
            id = "b2-1",
            label = "Launch OBS",
            actions = ActionList(
                actions = listOf(Action(launch_app = LaunchApp(path = "/Applications/OBS.app"))),
            ),
        )
        val toolsButton = Button(
            id = "b2",
            label = "Tools",
            folder = FolderContent(buttons = listOf(backButton, launchButton)),
        )

        val page = Page(id = "pg1", name = "Main", buttons = listOf(recordButton, toolsButton))
        val profile = Profile(id = "p1", name = "Streaming", pages = listOf(page))
        return Config(profiles = listOf(profile), active_profile_id = "p1")
    }

    @Test
    fun roundTripPreservesFullConfig() {
        val original = sampleConfig()
        val bytes = Config.ADAPTER.encode(original)
        val decoded = Config.ADAPTER.decode(bytes)
        assertEquals(original, decoded)
    }

    // Presence case 1: nil-vs-empty-string must stay distinguishable
    // through the round trip (spec finding 3).
    @Test
    fun roundTripDistinguishesAbsentLabelFromEmptyLabel() {
        val absent = Button(id = "absent", back = Back())
        val empty = Button(id = "empty", label = "", back = Back())

        val absentDecoded = Button.ADAPTER.decode(Button.ADAPTER.encode(absent))
        val emptyDecoded = Button.ADAPTER.decode(Button.ADAPTER.encode(empty))

        assertNull(absentDecoded.label)
        assertEquals("", emptyDecoded.label)
        assertNotEquals(absentDecoded.label, emptyDecoded.label)
    }

    // Presence case 2: a `.back`-set `content` must stay distinguishable
    // from an unset `content` oneof (spec finding 1 / Implementation Notes
    // item 4). wire has no sealed oneof type — it's nullable
    // actions/folder/back fields with a runtime at-most-one-set check
    // (Implementation Notes item 8, confirmed empirically here) — so the
    // distinguishing check is "back is non-null" vs. "all three are null".
    @Test
    fun roundTripDistinguishesBackCaseFromUnsetOneof() {
        val backSet = Button(id = "back", back = Back())
        val unset = Button(id = "unset")

        val backDecoded = Button.ADAPTER.decode(Button.ADAPTER.encode(backSet))
        val unsetDecoded = Button.ADAPTER.decode(Button.ADAPTER.encode(unset))

        assertNotNull(backDecoded.back)
        assertNull(unsetDecoded.actions)
        assertNull(unsetDecoded.folder)
        assertNull(unsetDecoded.back)
    }
}
