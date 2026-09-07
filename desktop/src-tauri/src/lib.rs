mod config;

use config::Button;

#[tauri::command]
fn list_buttons(app: tauri::AppHandle) -> Result<Vec<Button>, String> {
    config::load_buttons(&app)
}

#[tauri::command]
fn save_button(app: tauri::AppHandle, button: Button) -> Result<(), String> {
    let mut buttons = config::load_buttons(&app)?;
    match buttons.iter_mut().find(|b| b.id == button.id) {
        Some(existing) => *existing = button,
        None => buttons.push(button),
    }
    config::save_buttons(&app, &buttons)
}

#[tauri::command]
fn delete_button(app: tauri::AppHandle, id: String) -> Result<(), String> {
    let mut buttons = config::load_buttons(&app)?;
    buttons.retain(|b| b.id != id);
    config::save_buttons(&app, &buttons)
}

#[tauri::command]
fn reorder_buttons(app: tauri::AppHandle, order: Vec<String>) -> Result<(), String> {
    let buttons = config::load_buttons(&app)?;
    let reordered = order
        .iter()
        .filter_map(|id| buttons.iter().find(|b| &b.id == id).cloned())
        .collect::<Vec<_>>();
    config::save_buttons(&app, &reordered)
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .invoke_handler(tauri::generate_handler![
            list_buttons,
            save_button,
            delete_button,
            reorder_buttons
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
