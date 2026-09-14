use serde::{Deserialize, Serialize};
use std::fs;
use std::path::Path;
use std::sync::atomic::{AtomicU64, Ordering};

#[derive(Serialize, Deserialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct Config {
    pub profiles: Vec<Profile>,
    pub active_profile_id: String,
}

#[derive(Serialize, Deserialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct Profile {
    pub id: String,
    pub name: String,
    pub pages: Vec<Page>,
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
    /// Depth-first search over the active Profile's Pages (and nested
    /// folders) for a Button by id. Returns its actions, or `None` if the
    /// id doesn't exist (deleted since connect, or from a stale mobile
    /// cache) or isn't an `.actions` button. See slice 08 spec, §
    /// Implementation Notes.
    pub fn actions_for_button(&self, button_id: &str) -> Option<&[Action]> {
        let profile = self
            .profiles
            .iter()
            .find(|p| p.id == self.active_profile_id)?;
        profile
            .pages
            .iter()
            .find_map(|page| find_actions(&page.buttons, button_id))
    }
}

fn find_actions<'a>(buttons: &'a [Button], button_id: &str) -> Option<&'a [Action]> {
    for button in buttons {
        if button.id == button_id {
            return match &button.content {
                ButtonContent::Actions { actions } => Some(actions.as_slice()),
                _ => None,
            };
        }
        if let ButtonContent::Folder { buttons: nested } = &button.content {
            if let Some(found) = find_actions(nested, button_id) {
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
        }],
        active_profile_id: profile_id,
    }
}

pub fn load_config(config_path: &Path) -> Result<Config, String> {
    if !config_path.exists() {
        return Ok(default_config());
    }
    let data = fs::read_to_string(config_path).map_err(|e| e.to_string())?;
    serde_json::from_str(&data).map_err(|e| e.to_string())
}

pub fn save_config(config_path: &Path, config: &Config) -> Result<(), String> {
    let data = serde_json::to_string_pretty(config).map_err(|e| e.to_string())?;
    fs::write(config_path, data).map_err(|e| e.to_string())
}
