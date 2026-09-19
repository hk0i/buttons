use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, HashMap};
use std::fs;
use std::path::Path;
use std::sync::atomic::{AtomicU64, Ordering};

#[derive(Serialize, Deserialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct Config {
    pub profiles: Vec<Profile>,
    pub active_profile_id: String,
}

#[derive(Clone, PartialEq, Eq, PartialOrd, Ord)]
pub enum Platform {
    MacOs,
    Other(String),
}

impl Platform {
    pub fn wire_key(&self) -> &str {
        match self {
            Platform::MacOs => "macos",
            Platform::Other(s) => s.as_str(),
        }
    }

    #[cfg(target_os = "macos")]
    pub fn current() -> Option<Platform> {
        Some(Platform::MacOs)
    }

    #[cfg(not(target_os = "macos"))]
    pub fn current() -> Option<Platform> {
        None
    }
}

impl Serialize for Platform {
    fn serialize<S: serde::Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        serializer.serialize_str(self.wire_key())
    }
}

impl<'de> Deserialize<'de> for Platform {
    fn deserialize<D: serde::Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        let s = String::deserialize(deserializer)?;
        Ok(match s.as_str() {
            "macos" => Platform::MacOs,
            _ => Platform::Other(s),
        })
    }
}

#[derive(Serialize, Deserialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct Profile {
    pub id: String,
    pub name: String,
    pub pages: Vec<Page>,
    #[serde(default)]
    pub associated_app_by_platform: BTreeMap<Platform, String>,
}

#[derive(Serialize, Deserialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct Page {
    pub id: String,
    pub name: Option<String>,
    pub buttons: Vec<Button>,
}

#[derive(Serialize, Deserialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct Button {
    pub id: String,
    pub label: Option<String>,
    pub icon: Option<String>, // emoji/text glyph, per slice 2's mockButtons.ts convention
    pub content: ButtonContent,
}

#[derive(Serialize, Deserialize, Clone)]
#[serde(tag = "type", rename_all = "camelCase")]
pub enum ButtonContent {
    Actions { actions: Vec<Action> },
    Folder { buttons: Vec<Button> }, // buttons[0] is always Back — see new_folder_buttons
    Back,                            // no payload; pops one level off the nav stack
    // Two-state toggle, capped at two states (matching Elgato's own "Multi
    // Action Switch" limit) — see slice 09 spec Scope → Out #3.
    Switch { off: SwitchState, on: SwitchState },
}

/// Mirrors `Button`'s own `label`/`icon` shape plus a bare `actions` list —
/// no nested `ActionList` wrapper, since this isn't a oneof case competing
/// with `Folder`/`Back`. Matches the wire `SwitchState` exactly.
#[derive(Serialize, Deserialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct SwitchState {
    pub label: Option<String>,
    pub icon: Option<String>,
    pub actions: Vec<Action>,
}

#[derive(Serialize, Deserialize, Clone)]
#[serde(tag = "type", rename_all = "camelCase")]
pub enum Action {
    LaunchApp { path: String },
    Hotkey { keys: Vec<String> }, // e.g. ["cmd", "shift", "s"]; F13-F24 by name
    MediaKey { key: MediaKeyKind },
}

#[derive(Serialize, Deserialize, Clone)]
#[serde(rename_all = "camelCase")]
pub enum MediaKeyKind {
    PlayPause,
    Mute,
    NextTrack,
    PreviousTrack,
}

impl Config {
    /// Which actions a press on `button_id` should run right now, and (for
    /// a Switch) what a successful run flips to. `current_states` supplies
    /// live Switch indices (button_id -> is "on" showing); absent means
    /// off, matching `switch_state.json`'s own default. The one function
    /// both a real `ButtonPress` (`server.rs`) and the editor's `Test`
    /// button (`lib.rs`) call — see slice 09 spec, § Interface Note 3.
    pub fn press_target<'a>(
        &'a self,
        button_id: &str,
        current_states: &HashMap<String, bool>,
    ) -> Option<PressTarget<'a>> {
        let profile = self
            .profiles
            .iter()
            .find(|p| p.id == self.active_profile_id)?;
        profile
            .pages
            .iter()
            .find_map(|page| find_press_target(&page.buttons, button_id, current_states))
    }
}

/// `press_target`'s return type — plain data, no behavior of its own. See
/// slice 09 spec, § Interface Note 4.
pub struct PressTarget<'a> {
    pub actions: &'a [Action],
    /// `Some(new_value)` for a Switch (flip iff the run succeeds); `None`
    /// for a plain `.actions` button — nothing to flip.
    pub flips_to: Option<bool>,
}

fn find_press_target<'a>(
    buttons: &'a [Button],
    button_id: &str,
    current_states: &HashMap<String, bool>,
) -> Option<PressTarget<'a>> {
    for button in buttons {
        if button.id == button_id {
            return match &button.content {
                ButtonContent::Actions { actions } => Some(PressTarget {
                    actions: actions.as_slice(),
                    flips_to: None,
                }),
                ButtonContent::Switch { off, on } => {
                    let is_on = current_states.get(button_id).copied().unwrap_or(false);
                    let state = if is_on { on } else { off };
                    Some(PressTarget {
                        actions: state.actions.as_slice(),
                        flips_to: Some(!is_on),
                    })
                }
                _ => None,
            };
        }
        if let ButtonContent::Folder { buttons: nested } = &button.content {
            if let Some(found) = find_press_target(nested, button_id, current_states) {
                return Some(found);
            }
        }
    }
    None
}

static ID_COUNTER: AtomicU64 = AtomicU64::new(0);

fn new_id(prefix: &str) -> String {
    let n = ID_COUNTER.fetch_add(1, Ordering::Relaxed);
    format!("{prefix}-{n}")
}

/// Builds a new folder's initial `buttons` vec: a single real Back button at
/// index 0. Single source of truth for "every folder starts with a Back
/// button" — see slice 4 spec's Interface section.
pub fn new_folder_buttons() -> Vec<Button> {
    vec![Button {
        id: new_id("back"),
        label: None,
        icon: None,
        content: ButtonContent::Back,
    }]
}

fn default_config() -> Config {
    let profile_id = new_id("profile");
    Config {
        profiles: vec![Profile {
            id: profile_id.clone(),
            name: "Default Profile".to_string(),
            pages: vec![Page {
                id: new_id("page"),
                name: None,
                buttons: Vec::new(),
            }],
            associated_app_by_platform: BTreeMap::new(),
        }],
        active_profile_id: profile_id,
    }
}

pub fn load_config(config_path: &Path) -> Result<Config, String> {
    if !config_path.exists() {
        return Ok(default_config());
    }
    let data = fs::read_to_string(config_path).map_err(|e| e.to_string())?;
    let config: Config = serde_json::from_str(&data).map_err(|e| e.to_string())?;
    for profile in &config.profiles {
        for platform in profile.associated_app_by_platform.keys() {
            if let Platform::Other(unrecognized) = platform {
                eprintln!(
                    "config: unrecognized platform key {unrecognized:?} in profile {}",
                    profile.id
                );
            }
        }
    }
    Ok(config)
}

pub fn save_config(config_path: &Path, config: &Config) -> Result<(), String> {
    let data = serde_json::to_string_pretty(config).map_err(|e| e.to_string())?;
    fs::write(config_path, data).map_err(|e| e.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn two_distinct_unknown_platform_keys_both_survive() {
        let json = r#"{
            "profiles": [{
                "id": "p1",
                "name": "Test",
                "pages": [],
                "associatedAppByPlatform": {"macos": "com.x", "fake_platform_1": "y.exe", "fake_platform_2": "z"}
            }],
            "activeProfileId": "p1"
        }"#;
        let config: Config = serde_json::from_str(json).unwrap();
        let map = &config.profiles[0].associated_app_by_platform;
        assert_eq!(map.len(), 3);
        assert_eq!(map.get(&Platform::MacOs).unwrap(), "com.x");
        assert_eq!(map.get(&Platform::Other("fake_platform_1".to_string())).unwrap(), "y.exe");
        assert_eq!(map.get(&Platform::Other("fake_platform_2".to_string())).unwrap(), "z");
        let round_tripped: serde_json::Value = serde_json::from_str(&serde_json::to_string(&config).unwrap()).unwrap();
        let out_map = &round_tripped["profiles"][0]["associatedAppByPlatform"];
        assert_eq!(out_map["macos"], "com.x");
        assert_eq!(out_map["fake_platform_1"], "y.exe");
        assert_eq!(out_map["fake_platform_2"], "z");
    }
}
