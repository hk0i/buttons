use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;
use tauri::{AppHandle, Manager};

#[derive(Serialize, Deserialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct Button {
    pub id: String,
    pub label: Option<String>,
    pub icon: Option<String>, // emoji/text glyph, per slice 2's mockButtons.ts convention
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

fn config_path(app: &AppHandle) -> Result<PathBuf, String> {
    let dir = app.path().app_config_dir().map_err(|e| e.to_string())?;
    fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    Ok(dir.join("buttons.json"))
}

pub fn load_buttons(app: &AppHandle) -> Result<Vec<Button>, String> {
    let path = config_path(app)?;
    if !path.exists() {
        return Ok(Vec::new());
    }
    let data = fs::read_to_string(&path).map_err(|e| e.to_string())?;
    serde_json::from_str(&data).map_err(|e| e.to_string())
}

pub fn save_buttons(app: &AppHandle, buttons: &[Button]) -> Result<(), String> {
    let path = config_path(app)?;
    let data = serde_json::to_string_pretty(buttons).map_err(|e| e.to_string())?;
    fs::write(&path, data).map_err(|e| e.to_string())
}
