mod actions;
mod config;

use config::Button;
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
fn list_buttons(app: tauri::AppHandle) -> Result<Vec<Button>, String> {
    config::load_buttons(&config_path(&app)?)
}

#[tauri::command]
fn save_button(app: tauri::AppHandle, button: Button) -> Result<(), String> {
    let path = config_path(&app)?;
    let mut buttons = config::load_buttons(&path)?;
    match buttons.iter_mut().find(|b| b.id == button.id) {
        Some(existing) => *existing = button,
        None => buttons.push(button),
    }
    config::save_buttons(&path, &buttons)
}

#[tauri::command]
fn delete_button(app: tauri::AppHandle, id: String) -> Result<(), String> {
    let path = config_path(&app)?;
    let mut buttons = config::load_buttons(&path)?;
    buttons.retain(|b| b.id != id);
    config::save_buttons(&path, &buttons)
}

#[tauri::command]
fn reorder_buttons(app: tauri::AppHandle, order: Vec<String>) -> Result<(), String> {
    let path = config_path(&app)?;
    let buttons = config::load_buttons(&path)?;
    let reordered = order
        .iter()
        .filter_map(|id| buttons.iter().find(|b| &b.id == id).cloned())
        .collect::<Vec<_>>();
    config::save_buttons(&path, &reordered)
}

#[tauri::command]
fn press_button(app: tauri::AppHandle, id: String) -> Result<(), String> {
    let path = config_path(&app)?;
    let buttons = config::load_buttons(&path)?;
    let button = buttons
        .iter()
        .find(|b| b.id == id)
        .ok_or_else(|| format!("no such button: {id}"))?;
    actions::run(&button.actions)
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_dialog::init())
        .invoke_handler(tauri::generate_handler![
            list_buttons,
            save_button,
            delete_button,
            reorder_buttons,
            press_button
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
