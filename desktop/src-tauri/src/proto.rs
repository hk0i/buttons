//! Bridge between `config.rs`'s hand-written local-persistence types and
//! the generated wire types. `buttons::Config` (wire) and `config::Config`
//! (local) stay two distinct types this slice — this file is the only
//! place they touch, one direction (local -> wire, for `ConfigSync`). No
//! reverse mapping needed yet (that's `button_press`/`profile_switch`,
//! steps 8-10).

use crate::config;

// buttons.proto and wire.proto share proto package `buttons`, so
// prost_build/pbjson_build emit one generated file for both — see
// build.rs and slice 07 spec, § Scope → In, "Desktop: real prost codegen
// wired into `desktop/src-tauri`." Config/Profile/Page/Button/Action live
// here right alongside Envelope/PairRequest/PairResponse/ConfigSync.
pub mod buttons {
    include!(concat!(env!("OUT_DIR"), "/buttons.rs"));
    // pbjson_build's canonical-proto3-JSON Serialize/Deserialize impls
    // reference these types unqualified — must land in the same module.
    include!(concat!(env!("OUT_DIR"), "/buttons.serde.rs"));
}

impl From<&config::Config> for buttons::Config {
    fn from(c: &config::Config) -> Self {
        buttons::Config {
            profiles: c.profiles.iter().map(buttons::Profile::from).collect(),
            active_profile_id: c.active_profile_id.clone(),
        }
    }
}

impl From<&config::Profile> for buttons::Profile {
    fn from(p: &config::Profile) -> Self {
        buttons::Profile {
            id: p.id.clone(),
            name: p.name.clone(),
            pages: p.pages.iter().map(buttons::Page::from).collect(),
        }
    }
}

impl From<&config::Page> for buttons::Page {
    fn from(p: &config::Page) -> Self {
        buttons::Page {
            id: p.id.clone(),
            name: p.name.clone(),
            buttons: p.buttons.iter().map(buttons::Button::from).collect(),
        }
    }
}

impl From<&config::Button> for buttons::Button {
    fn from(b: &config::Button) -> Self {
        buttons::Button {
            id: b.id.clone(),
            label: b.label.clone(),
            icon: b.icon.clone(),
            // Scoped to .switch_content buttons only; a plain
            // .actions/.folder/.back button always reports false and
            // mobile never reads it (slice 09 spec, § Implementation
            // Notes #6). Always false here regardless of content — this
            // `From` stays pure/persisted-only and has no access to live
            // SwitchStates; `apply_switch_states` below is the post-pass
            // that fills in the real value at config_sync send time.
            is_active: false,
            content: Some(buttons::button::Content::from(&b.content)),
        }
    }
}

impl From<&config::ButtonContent> for buttons::button::Content {
    fn from(c: &config::ButtonContent) -> Self {
        match c {
            config::ButtonContent::Actions { actions } => {
                buttons::button::Content::Actions(buttons::ActionList {
                    actions: actions.iter().map(buttons::Action::from).collect(),
                })
            }
            config::ButtonContent::Folder { buttons: folder_buttons } => {
                buttons::button::Content::Folder(buttons::FolderContent {
                    buttons: folder_buttons.iter().map(buttons::Button::from).collect(),
                })
            }
            // no payload; empty message case must stay Some(Back{}), not
            // None — see protocol/verify-rust's presence round-trip test.
            config::ButtonContent::Back => buttons::button::Content::Back(buttons::Back {}),
            config::ButtonContent::Switch { off, on } => {
                buttons::button::Content::SwitchContent(buttons::SwitchContent {
                    off: Some(buttons::SwitchState::from(off)),
                    on: Some(buttons::SwitchState::from(on)),
                })
            }
        }
    }
}

impl From<&config::SwitchState> for buttons::SwitchState {
    fn from(s: &config::SwitchState) -> Self {
        buttons::SwitchState {
            label: s.label.clone(),
            icon: s.icon.clone(),
            actions: s.actions.iter().map(buttons::Action::from).collect(),
        }
    }
}

impl From<&config::Action> for buttons::Action {
    fn from(a: &config::Action) -> Self {
        buttons::Action {
            action: Some(buttons::action::Action::from(a)),
        }
    }
}

impl From<&config::Action> for buttons::action::Action {
    fn from(a: &config::Action) -> Self {
        match a {
            config::Action::LaunchApp { path } => {
                buttons::action::Action::LaunchApp(buttons::LaunchApp { path: path.clone() })
            }
            config::Action::Hotkey { keys } => {
                buttons::action::Action::Hotkey(buttons::Hotkey { keys: keys.clone() })
            }
            config::Action::MediaKey { key } => {
                buttons::action::Action::MediaKey(buttons::MediaKeyKind::from(key) as i32)
            }
        }
    }
}

impl From<&config::MediaKeyKind> for buttons::MediaKeyKind {
    fn from(k: &config::MediaKeyKind) -> Self {
        match k {
            config::MediaKeyKind::PlayPause => buttons::MediaKeyKind::PlayPause,
            config::MediaKeyKind::Mute => buttons::MediaKeyKind::Mute,
            config::MediaKeyKind::NextTrack => buttons::MediaKeyKind::NextTrack,
            config::MediaKeyKind::PreviousTrack => buttons::MediaKeyKind::PreviousTrack,
        }
    }
}

/// Merges live `SwitchStates` into an already-built proto `Config`, for
/// `ConfigSync`. `From<&config::Config>` above stays pure/persisted-only —
/// it has no access to `SwitchStates` and shouldn't gain one; this
/// post-pass runs immediately after, at every `config_sync` send site.
/// **The seam this whole slice turns on** — a future reader reaching for
/// "just thread the map into `From`" should land here instead of
/// rediscovering the wall. See slice 09 spec, § Interface Note 6.
pub fn apply_switch_states(config: &mut buttons::Config, states: &crate::switch_state::SwitchStates) {
    let map = states.lock().unwrap();
    for profile in &mut config.profiles {
        for page in &mut profile.pages {
            apply_switch_states_to_buttons(&mut page.buttons, &map);
        }
    }
}

fn apply_switch_states_to_buttons(
    buttons: &mut [buttons::Button],
    map: &std::collections::HashMap<String, bool>,
) {
    for button in buttons {
        if let Some(is_on) = map.get(&button.id) {
            button.is_active = *is_on;
        }
        if let Some(buttons::button::Content::Folder(folder)) = &mut button.content {
            apply_switch_states_to_buttons(&mut folder.buttons, map);
        }
    }
}

/// `server.rs` assumes `serde_json::from_str::<Envelope>` parses what
/// swift-protobuf's `jsonString()` emits on the other end of the wire —
/// never actually exercised end-to-end before a real iPhone is in the
/// loop. These pin the two places canonical proto3 JSON has real rules:
/// `optional` presence (an absent field is omitted, not `null`) and
/// `oneof` representation (one key per case, not a tag + payload).
#[cfg(test)]
mod wire_json_tests {
    use super::buttons;

    #[test]
    fn envelope_pair_response_round_trips_through_json() {
        let original = buttons::Envelope {
            protocol_version: "1".to_string(),
            message: Some(buttons::envelope::Message::PairResponse(
                buttons::PairResponse {
                    ok: true,
                    auth_token: Some("secret".to_string()),
                    error: None,
                },
            )),
        };

        let json = serde_json::to_string(&original).expect("serialize");
        assert!(json.contains("authToken"), "expected lowerCamelCase field name: {json}");
        assert!(!json.contains("\"error\""), "absent optional must be omitted, not null: {json}");

        let decoded: buttons::Envelope = serde_json::from_str(&json).expect("deserialize");
        assert_eq!(decoded, original);
    }

    #[test]
    fn envelope_deserializes_snake_case_field_names_too() {
        // Confirms this side isn't accidentally relying on swift-protobuf
        // emitting exactly the same casing pbjson does — both directions
        // of the proto3 JSON mapping are accepted on read.
        let json = r#"{ "protocol_version": "1", "pair_request": { "token": "abc" } }"#;
        let decoded: buttons::Envelope = serde_json::from_str(json).expect("deserialize");
        assert_eq!(decoded.protocol_version, "1");
        assert!(matches!(
            decoded.message,
            Some(buttons::envelope::Message::PairRequest(ref pr)) if pr.token == "abc"
        ));
    }
}
