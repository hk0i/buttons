mod actions;
mod config;
mod pairing;
mod proto;

use config::{Action, Config};
use std::fs;
use std::path::PathBuf;
use tauri::{AppHandle, Manager};

/// Tauri-specific glue, kept out of `config.rs` so its data/persistence logic
/// stays plain Rust — reusable as-is if the UI layer ever changes.
fn config_path(app: &AppHandle) -> Result<PathBuf, String> {
    let dir = app.path().app_config_dir().map_err(|e| e.to_string())?;
    fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    Ok(dir.join("buttons.json"))
}

#[tauri::command]
fn get_config(app: tauri::AppHandle) -> Result<Config, String> {
    config::load_config(&config_path(&app)?)
}

#[tauri::command]
fn save_config(app: tauri::AppHandle, config: Config) -> Result<(), String> {
    config::save_config(&config_path(&app)?, &config)
}

#[tauri::command]
fn run_actions(actions: Vec<Action>) -> Result<(), String> {
    actions::run(&actions)
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_dialog::init())
        .invoke_handler(tauri::generate_handler![get_config, save_config, run_actions])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
