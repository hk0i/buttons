mod actions;
mod config;
mod pairing;
mod proto;
mod server;

use config::{Action, Config};
use pairing::Pairing;
use serde::Serialize;
use std::fs;
use std::path::PathBuf;
use std::sync::Arc;
use tauri::{AppHandle, Manager};

/// Tauri-specific glue, kept out of `config.rs` so its data/persistence logic
/// stays plain Rust — reusable as-is if the UI layer ever changes.
fn config_path(app: &AppHandle) -> Result<PathBuf, String> {
    let dir = app.path().app_config_dir().map_err(|e| e.to_string())?;
    fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    Ok(dir.join("buttons.json"))
}

/// Beside `buttons.json`, same directory — genuine device-local settings
/// per EDD §5.3, not `localStorage`.
fn device_path(app: &AppHandle) -> Result<PathBuf, String> {
    let dir = app.path().app_config_dir().map_err(|e| e.to_string())?;
    fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    Ok(dir.join("device.json"))
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

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct PairingQr {
    svg: String,
    payload: String,
}

/// Issues a fresh one-time pairing token and renders it as an SVG QR —
/// server-side (`qrcode` crate), no client-side QR library. Called each
/// time the pairing view (re)opens; the previous token is invalidated the
/// moment this runs, not left valid until its TTL expires.
#[tauri::command]
fn get_pairing_qr(pairing: tauri::State<Arc<Pairing>>) -> Result<PairingQr, String> {
    let token = pairing.issue_pairing_token();
    // "<device_id> <lan_ip> <port> <pairing_token>" — see wire.proto's
    // Interface section for why this is 4 space-delimited fields, not
    // ip:port colon-joined. Named holes, not positional `{}` — field order
    // here must match iOS's split-by-space parse; a reorder is silent
    // with positional args, not with named ones.
    let device_id = pairing.device_id();
    let ip = server::local_ip();
    let port = server::PORT;
    let payload = format!("{device_id} {ip} {port} {token}");
    let code = qrcode::QrCode::new(payload.as_bytes()).map_err(|e| e.to_string())?;
    let svg = code.render::<qrcode::render::svg::Color>().build();
    Ok(PairingQr { svg, payload })
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_dialog::init())
        .setup(|app| {
            let handle = app.handle();
            let config_path = config_path(handle)?;
            let device_path = device_path(handle)?;
            let pairing = Arc::new(Pairing::load_or_create(device_path)?);
            app.manage(Arc::clone(&pairing));
            tauri::async_runtime::spawn(server::run(pairing, config_path));
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            get_config,
            save_config,
            run_actions,
            get_pairing_qr
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
