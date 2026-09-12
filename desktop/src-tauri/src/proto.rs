//! Bridge between `config.rs`'s hand-written local-persistence types and
//! the generated wire types. Per slice 07 spec Implementation Notes #6:
//! `buttons::Config` (wire) and `config::Config` (local) stay two distinct
//! types this slice — this file is the only place they touch, one
//! direction (local -> wire, for `ConfigSync`). No reverse mapping needed
//! yet (that's `button_press`/`profile_switch`, steps 8-10).

use crate::config;

// buttons.proto and wire.proto share proto package `buttons`, so
// prost_build/pbjson_build emit one generated file for both — see
// build.rs and docs/slices/07. Discovery, Pairing & Config Sync.spec.md
// Scope → In item 2. Config/Profile/Page/Button/Action live here right
// alongside Envelope/PairRequest/PairResponse/ConfigSync.
pub mod buttons {
    include!(concat!(env!("OUT_DIR"), "/buttons.rs"));
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
